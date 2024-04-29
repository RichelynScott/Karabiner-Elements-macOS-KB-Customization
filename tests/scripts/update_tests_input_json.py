#!/usr/bin/python3

'''Script to batch update `input_event_queue/*.json`'''

import sys
import json


def migrate(paths):
    '''
    - Remove event_origin
    '''

    for path in paths:
        with open(path, encoding='utf-8') as file:
            j = json.load(file)
            for entry in j:
                if 'event_origin' in entry:
                    del entry['event_origin']

            with open(path, 'w', encoding='utf-8') as output:
                json.dump(j, output, sort_keys=True, indent=4)


if __name__ == "__main__":
    migrate(sys.argv[1:])
