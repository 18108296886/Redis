#!/usr/bin/env python3
import argparse
import json
import subprocess
from collections import OrderedDict
from sys import argv, stdin
import os


def convert_flags_to_boolean_dict(flags):
    """Return a dict with a key set to `True` per element in the flags list."""
    return {f: True for f in flags}


def set_if_not_none_or_empty(dst, key, value):
    """Set 'key' in 'dst' if 'value' is not `None` or an empty list."""
    if value is not None and (type(value) is not list or len(value)):
        dst[key] = value


def convert_argument(arg):
    """Transform an argument."""
    arg.update(convert_flags_to_boolean_dict(arg.pop('flags', [])))
    set_if_not_none_or_empty(arg, 'arguments',
                             [convert_argument(x) for x in arg.pop('arguments', [])])
    return arg


def convert_keyspec(spec):
    """Transform a key spec."""
    spec.update(convert_flags_to_boolean_dict(spec.pop('flags', [])))
    return spec


def convert_entry_to_objects_array(container, cmd, details):
    """Transform the JSON output of `COMMAND` to a friendlier format.

    cmd is the output of `COMMAND` as follows:
    1. Name (lower case, e.g. "lolwut")
    2. Arity
    3. Flags
    4-6. First/last/step key specification (deprecated as of Redis v7.0)
    7. ACL categories
    8. hints (as of Redis 7.0)
    9. key-specs (as of Redis 7.0)
    10. subcommands (as of Redis 7.0)

    details is the output of `COMMAND DETAILS`, which holds a map of additional metadata

    This returns a list with a dict for the command and per each of its
    subcommands. Each dict contains one key, the command's full name, with a
    value of a dict that's set with the command's properties and meta
    information."""
    assert len(cmd) >= 9
    obj = {}
    rep = [obj]
    name = cmd[0].upper()
    arity = cmd[1]
    command_flags = cmd[2]
    acl_categories = cmd[6]
    hints = cmd[7]
    keyspecs = cmd[8]
    subcommands = cmd[9] if len(cmd) > 9 else []
    key = f'{container} {name}' if container else name

    subcommand_details = details.pop('subcommands', [])
    rep.extend([convert_entry_to_objects_array(name, x, subcommand_details[x[0]])[0] for x in subcommands])

    # The command's value is ordered so the interesting stuff that we care about
    # is at the start. Optional `None` and empty list values are filtered out.
    value = OrderedDict()
    value['summary'] = details.pop('summary')
    value['since'] = details.pop('since')
    value['group'] = details.pop('group')
    set_if_not_none_or_empty(value, 'complexity', details.pop('complexity', None))
    set_if_not_none_or_empty(value, 'deprecated_since', details.pop('deprecated_since', None))
    set_if_not_none_or_empty(value, 'replaced_by', details.pop('replaced_by', None))
    set_if_not_none_or_empty(value, 'history', details.pop('history', []))
    set_if_not_none_or_empty(value, 'acl_categories', acl_categories)
    value['arity'] = arity
    set_if_not_none_or_empty(value, 'key_specs',
                             [convert_keyspec(x) for x in keyspecs])
    set_if_not_none_or_empty(value, 'arguments',
                             [convert_argument(x) for x in details.pop('arguments', [])])
    set_if_not_none_or_empty(value, 'command_flags', command_flags)
    set_if_not_none_or_empty(value, 'doc_flags', details.pop('doc_flags', []))
    set_if_not_none_or_empty(value, 'hints', hints)

    # All remaining details key-value tuples, if any, are appended to the command
    # to be future-proof.
    while len(details) > 0:
        (k, v) = details.popitem()
        value[k] = v

    obj[key] = value
    return rep


# Figure out where the sources are
srcdir = os.path.abspath(os.path.dirname(os.path.abspath(__file__)) + "/../src")

# MAIN
if __name__ == '__main__':
    opts = {
        'description': 'Transform the output from `redis-cli --json` using COMMAND and COMMAND DETAILS to a single commands.json format.',
        'epilog': f'Usage example: {argv[0]} --cli src/redis-cli --port 6379 > commands.json'
    }
    parser = argparse.ArgumentParser(**opts)
    parser.add_argument('--host', type=str, default='localhost')
    parser.add_argument('--port', type=int, default=6379)
    parser.add_argument('--cli', type=str, default='%s/redis-cli' % srcdir)
    args = parser.parse_args()

    payload = OrderedDict()
    cmds = []

    p = subprocess.Popen([args.cli, '-h', args.host, '-p', str(args.port), '--json', 'command'], stdout=subprocess.PIPE)
    stdout, stderr = p.communicate()
    commands = json.loads(stdout)

    p = subprocess.Popen([args.cli, '-h', args.host, '-p', str(args.port), '--json', 'command', 'details'], stdout=subprocess.PIPE)
    stdout, stderr = p.communicate()
    details = json.loads(stdout)

    for entry in commands:
        cmd = convert_entry_to_objects_array(None, entry, details[entry[0]])
        cmds.extend(cmd)

    # The final output is a dict of all commands, ordered by name.
    cmds.sort(key=lambda x: list(x.keys())[0])
    for cmd in cmds:
        name = list(cmd.keys())[0]
        payload[name] = cmd[name]

    print(json.dumps(payload, indent=4))
