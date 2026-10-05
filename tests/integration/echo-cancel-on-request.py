#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Isolated PipeWire/PulseAudio/WirePlumber routing and lifecycle test.

Uses synthetic devices, not a real microphone. It does not measure acoustic AEC
quality and does not substitute for Librem 5 / Mobian hardware validation.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

PREFIX = Path(os.environ["WP_TEST_PREFIX"])
MODE = os.environ.get("WP_ECHO_TEST_MODE", "configured")
processes = []
logs = []
checks = 0


def check(condition, description):
    global checks
    if not condition:
        raise AssertionError(description)
    checks += 1
    print("PASS:", description, flush=True)


def spawn(argv, name, **kwargs):
    log = open(work / (name + ".log"), "w")
    logs.append(log)
    p = subprocess.Popen(argv, env=env, stderr=log,
                         stdout=kwargs.pop("stdout", log), **kwargs)
    processes.append(p)
    return p


def snapshot():
    result = subprocess.run([str(PREFIX / "bin/pw-dump")], env=env,
                            capture_output=True, text=True, timeout=5)
    if result.returncode != 0 or not result.stdout.strip():
        return []
    return json.loads(result.stdout)


def nodes(data):
    return {x["id"]: x for x in data if x["type"] == "PipeWire:Interface:Node"}


def name_of(node):
    return node["info"]["props"].get("node.name", "")


def node_id(data, name):
    for ident, node in nodes(data).items():
        props = node["info"]["props"]
        if props.get("node.name") == name or props.get("application.name") == name:
            return ident
    return None


def linked(data, source, target):
    src, dst = node_id(data, source), node_id(data, target)
    if src is None or dst is None:
        return False
    return any(x["type"] == "PipeWire:Interface:Link" and
               x["info"].get("output-node-id") == src and
               x["info"].get("input-node-id") == dst and
               x["info"].get("state") in ("active", "paused") for x in data)


def aec_nodes(data):
    return {name_of(n) for n in nodes(data).values()
            if name_of(n).startswith("wp.echo-cancel.")}


def wait_for(predicate, description, timeout=10):
    limit = time.monotonic() + timeout
    while time.monotonic() < limit:
        data = snapshot()
        if predicate(data):
            check(True, description)
            return data
        time.sleep(0.1)
    (work / "failed-graph.json").write_text(json.dumps(data, indent=2))
    raise AssertionError(description)


def stop(p):
    if p.poll() is None:
        p.terminate()
        try:
            p.wait(timeout=3)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait(timeout=3)


def stream(name, capture=False, properties=None, device=None):
    argv = ["parec" if capture else "pacat", "--raw", "--rate=48000",
            "--channels=1", "--format=s16le", "--client-name=" + name,
            "--property=application.name=" + name]
    if device:
        argv.append("--device=" + device)
    for key, value in (properties or {}).items():
        argv.append("--property=" + key + "=" + value)
    if capture:
        return spawn(argv, name, stdout=subprocess.DEVNULL)
    with open("/dev/zero", "rb") as silence:
        return spawn(argv, name, stdin=silence)


with tempfile.TemporaryDirectory(prefix="wp-echo-test-") as temporary:
    work = Path(temporary)
    runtime, home = work / "run", work / "home"
    runtime.mkdir(mode=0o700)
    home.mkdir()
    config = home / ".config"
    pwconf = config / "pipewire/pipewire.conf.d"
    wpconf = config / "wireplumber/wireplumber.conf.d"
    pwconf.mkdir(parents=True)
    wpconf.mkdir(parents=True)
    (pwconf / "test-devices.conf").write_text("""
context.spa-libs = { audiotestsrc = audiotestsrc/libspa-audiotestsrc }
context.objects = [
  { factory = adapter
    args = { factory.name = support.null-audio-sink node.name = ci.speaker
             media.class = Audio/Sink priority.session = 1000 audio.position = [ MONO ] } }
  { factory = adapter
    args = { factory.name = support.null-audio-sink node.name = ci.other
             media.class = Audio/Sink priority.session = 100 audio.position = [ MONO ] } }
  { factory = adapter
    args = { factory.name = audiotestsrc node.name = ci.mic
             media.class = Audio/Source audio.position = [ MONO ] } }
]
""")
    (wpconf / "on-request.conf").write_text("""
wireplumber.profiles = {
  main = {
    monitor.alsa = disabled
    monitor.bluez = disabled
    monitor.bluez-midi = disabled
    monitor.v4l2 = disabled
    monitor.libcamera = disabled
    hooks.node.echo-cancel = required
  }
}
""" + ("node.echo-cancel = { source = ci.mic sink = ci.speaker }" if MODE == "configured" else ""))
    env = dict(os.environ, HOME=str(home), XDG_RUNTIME_DIR=str(runtime),
               XDG_CONFIG_HOME=str(config), XDG_STATE_HOME=str(home / ".state"),
               WIREPLUMBER_DEBUG="3", PIPEWIRE_DEBUG="2")
    env.pop("PIPEWIRE_REMOTE", None)
    env.pop("PULSE_SERVER", None)
    try:
        spawn([str(PREFIX / "bin/pipewire")], "pipewire")
        wait_for(lambda d: node_id(d, "ci.speaker") is not None and
                 node_id(d, "ci.mic") is not None, "synthetic devices available")
        spawn([str(PREFIX / "bin/wireplumber")], "wireplumber")
        spawn([str(PREFIX / "bin/pipewire-pulse")], "pipewire-pulse")
        until = time.monotonic() + 10
        while time.monotonic() < until and not (runtime / "pulse/native").exists():
            time.sleep(0.1)
        check((runtime / "pulse/native").exists(), "PulseAudio socket ready")
        ordinary = stream("ci.ordinary")
        data = wait_for(lambda d: linked(d, "ci.ordinary", "ci.speaker"),
                        "ordinary PulseAudio playback uses the physical sink")
        check(not aec_nodes(data), "no AEC module loaded without a request")
        playback = stream("ci.want", properties={"filter.want": "echo-cancel"}, device="ci.speaker")
        capture = stream("ci.capture", capture=True, device="ci.mic",
                         properties={"filter.want": "echo-cancel"})
        data = wait_for(lambda d: linked(d, "ci.want", "wp.echo-cancel.sink") and
                        linked(d, "wp.echo-cancel.source", "ci.capture"),
                        "requested capture and playback route through real AEC module")
        check(len(aec_nodes(data)) == 4, "exactly one four-node AEC instance")
        check(linked(data, "ci.ordinary", "ci.speaker"),
              "unrelated playback is not redirected into AEC")
        check(linked(data, "ci.mic", "wp.echo-cancel.capture") and
              linked(data, "wp.echo-cancel.playback", "ci.speaker"),
              "AEC internal streams bind to their configured devices")
        forced = stream("ci.apply", properties={"filter.apply": "echo-cancel"})
        data = wait_for(lambda d: linked(d, "ci.apply", "wp.echo-cancel.sink"),
                        "explicit filter.apply uses the same filter")
        check(len(aec_nodes(data)) == 4, "requesters share one module")
        suppressed = stream("ci.suppressed", properties={"filter.want": "echo-cancel",
                                                       "filter.suppress": "echo-cancel"})
        wait_for(lambda d: linked(d, "ci.suppressed", "ci.speaker"),
                 "suppressed stream stays outside the AEC filter")
        unrelated = stream("ci.explicit-other", properties={"filter.want": "echo-cancel"}, device="ci.other")
        wait_for(lambda d: linked(d, "ci.explicit-other", "ci.other"),
                 "explicit unrelated device remains selected despite filter.want")
        stop(playback)
        data = wait_for(lambda d: node_id(d, "ci.want") is None,
                        "first requester removed")
        check(len(aec_nodes(data)) == 4, "module remains while other requesters exist")
        stop(capture)
        stop(forced)
        data = wait_for(lambda d: not aec_nodes(d), "module unloaded after last requester")
        check(linked(data, "ci.ordinary", "ci.speaker") and
              linked(data, "ci.suppressed", "ci.speaker"),
              "unload leaves unrelated streams connected")
        for i in range(3):
            p = stream("ci.repeat", properties={"filter.want": "echo-cancel"})
            wait_for(lambda d: linked(d, "ci.repeat", "wp.echo-cancel.sink"),
                     "repeated call %d loads and links" % (i + 1))
            stop(p)
            wait_for(lambda d: not aec_nodes(d),
                     "repeated call %d unloads cleanly" % (i + 1))
        print("INTEGRATION PASSED:", checks, "checks;", MODE, "pair; synthetic devices only", flush=True)
    except Exception:
        for p in processes:
            if p.poll() is not None:
                print("EXITED:", p.args, p.returncode, flush=True)
        for log in logs:
            log.flush()
        for path in work.glob("*.log"):
            print("---", path.name, "---", flush=True)
            print(path.read_text(errors="replace")[-14000:], flush=True)
        if (work / "failed-graph.json").exists():
            print((work / "failed-graph.json").read_text()[-24000:], flush=True)
        raise
    finally:
        for p in reversed(processes):
            stop(p)
        for log in logs:
            log.close()
