#!/usr/bin/env python3
import datetime
import sys

def check_seconds(file_path, target_date_str):
    # parse the target day
    day = datetime.datetime.strptime(target_date_str, "%Y-%m-%d").date()
    # define our window edges
    start = datetime.datetime.combine(day - datetime.timedelta(days=1),
                                      datetime.time(23, 50,  0))
    end   = datetime.datetime.combine(day,
                                      datetime.time(23, 59, 59))

    actual_epochs = 0
    expected_epochs = int((end - start).total_seconds()) + 1

    has_missing   = False
    previous_time = None

    with open(file_path, 'r') as f:
        for line in f:
            parts = line.split()
            if len(parts) < 8:
                continue

            # build a datetime from fields 1–6
            yy, mm, dd, hh, mi, ss = map(int, parts[1:7])
            if yy < 100:
                yy += 2000
            current = datetime.datetime(yy, mm, dd, hh, mi, ss)

            # skip anything outside our [start…end] window
            if current < start or current > end:
                continue

            actual_epochs += 1

            if previous_time is None:
                # first record in window: check for lead-in gap
                if current != start:
                    #print(f"Missing epochs between {start} and {current}")
                    has_missing = True
                previous_time = current
                continue

            # every subsequent record must be exactly +1s
            delta = (current - previous_time).total_seconds()
            if delta != 1:
                #print(f"Missing epochs between {previous_time} and {current}")
                has_missing = True

            previous_time = current

    # after reading: check for a tail gap up to 23:59:59
    if previous_time and previous_time < end:
        #print(f"Missing epochs between {previous_time} and {end}")
        has_missing = True
    if has_missing:
        print(f"Number of Epochs = {actual_epochs} | Expected Number of Epochs = {expected_epochs}")
        if actual_epochs == 0:
            actual_epochs = 1
    return actual_epochs if has_missing else 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: check_ems-doy.py <file_path> <YYYY-MM-DD>")
        sys.exit(2)
    rc = check_seconds(sys.argv[1], sys.argv[2])
    print(rc)
    sys.exit(rc)
