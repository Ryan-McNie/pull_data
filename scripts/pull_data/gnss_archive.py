#!/usr/bin/python3

import argparse
import base64
import datetime
import getpass
import json
import re
import sys
import urllib.parse
import urllib.request
from os import environ as env

# By default uses Production Domain.
GNSS_DOMAIN = "archive.geodesy.linz.govt.nz"

if env.get("ENVIRONMENT") == "nonprod":
    print("\033[94m[info]\033[0m: app is running in `nonprod` mode")
    GNSS_DOMAIN = "nonprod.gnss-archive.awsint.linz.govt.nz"  # Using Nonprod domain

DailyFrequencyMinutes = 60 * 24

authuri = f"https://search.{GNSS_DOMAIN}/v1/urlAuth"
datatype30sec = "rnx2_daily_30s"
datatype1sec = "rnx2_15min_01s"
search_url = f"https://search.{GNSS_DOMAIN}/v1/rinexFiles?access=[access]&startTime=[yyyy]/[ddd]&endTime=[yyyy+1]/[ddd+1]&dataType=[datatype]"
search_url_sitecodes = "&siteCodes=[sssss]"

debug = False


def main():
    global debug
    parser = argparse.ArgumentParser(
        description="Retrieve private file from GNSS archive",
        epilog='If a credentials file is used it should have two lines, "user username", and "password password".\n'
        "The credentials files can be defined using the GNSS_ARCHIVE_CREDENTIALS_FILE environment variable.\n"
        "If no credentials file is provided, the user will be prompted for a username and password.",
    )
    parser.add_argument(
        "epoch",
        metavar="YYYY:DDD",
        help="Year and day number to get, or range YYYY:DDD-YYYY:DDDD",
    )
    parser.add_argument("station", nargs="*", help="Station(s) to get")
    parser.add_argument(
        "-1", "--one-second-data", action="store_true", help="Retrieve 1 second data"
    )
    parser.add_argument(
        "-c",
        "--credentials-file",
        help="Optional user credentials file (or GNSS_ARCHIVE_CREDENTIALS_FILE ",
    )
    parser.add_argument(
        "-s",
        "--search",
        action="store_true",
        help="Search for files (only for one day)",
    )

    parser.add_argument("-g", "--debug", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    debug = args.debug
    ematch = re.match(
        r"^((?:19|20)\d\d)\:([0123]\d\d)(?:\-(?:((?:19|20)\d\d)\:)?([0123]\d\d))?$",
        args.epoch,
    )
    if not ematch:
        raise RuntimeError(f"Invalid epoch {args.epoch}")
    days = daysInRange(
        ematch.group(1), ematch.group(2), ematch.group(3), ematch.group(4)
    )
    period = datatype1sec if args.one_second_data else datatype30sec
    codes = args.station

    if args.search:
        yyyy, ddd = days[0]
        results = []
        for access in ["private", "public"]:
            searchlist = search_archive(access, period, yyyy, ddd, codes)
            results.extend(searchlist.get("results", []))
        print(json.dumps(results, indent=2))
        sys.exit(0)

    if not codes:
        print("No station codes specified for download")
        sys.exit(1)

    ucodes = set(code.upper() for code in codes)
    nocredcodes = set()
    credentials = False
    for yyyy, ddd in days:
        found = set()
        for access in ["private", "public"]:
            rinexfiles = search_archive(access, period, yyyy, ddd, codes)
            for rinexfile in rinexfiles.get("results", []):
                uri = rinexfile["fileUrl"]
                filename = rinexfile["fileName"]
                code = filename[:4].upper()
                cookies = None
                if access == "private":
                    if not credentials:
                        if credentials is False:
                            credentials = getCredentials(args.credentials_file)
                        if not credentials:
                            if code not in nocredcodes:
                                print(
                                    f"Credentials not provided for private archive: skipping {code}"
                                )
                                nocredcodes.add(code)
                                found.add(code)
                            continue
                    cookies = credentials
                if getFile(uri, cookies, filename):
                    found.add(code)
            missing = ucodes - found
        if missing:
            sys.exit(3)


def getCredentials(credentials_file=None):
    cookies = None
    while True:
        credentials_file = credentials_file or env.get("GNSS_ARCHIVE_CREDENTIALS_FILE")
        if credentials_file:
            user, passwd = readUserPwd(credentials_file)
            credentials_file = None
        else:
            print("Enter GNSS archive credentials to access private data")
            user = input("Username (or enter to skip private data): ")
            if not user:
                print("Username not provided - not accessing private data")
                break
            passwd = getpass.getpass("Password: ")
            if not passwd:
                break
        try:
            cookies = getAuthCookies(authuri, user, passwd)
            return cookies
        except Exception as ex:
            print("User name and password is not correct for GNSS archive")
    return None


def readUserPwd(credfile):
    user = None
    passwd = None
    with open(credfile) as ch:
        for l in ch:
            parts = l.strip().split()
            if len(parts) > 1:
                if parts[0] == "user":
                    user = parts[1]
                elif parts[0] == "password":
                    passwd = parts[1]
    if user is None or passwd is None:
        raise RuntimeError(f"Missing data in credentials file {credfile}")
    return user, passwd


def getAuthCookies(url, user, passwd):
    if debug:
        print(f"Retrieving authentication cookies from {url}")
    req = urllib.request.Request(url)
    credentials = "%s:%s" % (user, passwd)
    encoded_credentials = base64.b64encode(credentials.encode("ascii"))
    req.add_header("Authorization", "Basic %s" % encoded_credentials.decode("ascii"))
    with urllib.request.urlopen(req) as res:
        data = json.loads(res.read().decode("utf8"))
        return data["cookies"]


def getFile(url, cookies, filename):
    if debug:
        print(f"Retrieving data from {url}")
    req = urllib.request.Request(url)
    if cookies:
        req.add_header("Cookie", ";".join(cookies))
    try:
        with urllib.request.urlopen(req) as res:
            if res.status == 200:
                data = res.read()
                with open(filename, "wb") as fh:
                    fh.write(data)
                print(f"\rRetrieved {filename}", end="", flush=True)
                return True
            else:
                print(f"Could not get {filename}: {res.status}")
    except Exception as ex:
        print(f"Failed to retrieve {filename}: {ex}")
    return False


def daysInRange(y0, d0, y1, d1):
    y1 = y1 or y0
    d1 = d1 or d0
    if y1 == y0 and d1 == d0:
        return [(y0, d0)]
    days = []
    try:
        dt0 = datetime.datetime.strptime(f"{y0}:{d0}", "%Y:%j")
        dt1 = datetime.datetime.strptime(f"{y1}:{d1}", "%Y:%j")
        if dt1 < dt0:
            raise RuntimeError("Start date after end date")
        inc = datetime.timedelta(days=1)
        while dt0 <= dt1:
            days.append(dt0.strftime("%Y:%j").split(":"))
            dt0 += inc
        return days

    except Exception as ex:
        raise RuntimeError(f"Cannot process date range {y0}:{d0}-{y1}:{d1}: {ex}")


def search_archive(access, period, yyyy, ddd, sitecodes=[]):
    dayplus1 = datetime.datetime.strptime(
        f"{yyyy}:{ddd}", "%Y:%j"
    ) + datetime.timedelta(days=1)
    yyyy1 = dayplus1.strftime("%Y")
    ddd1 = dayplus1.strftime("%j")
    replacments = {
        "access": access,
        "datatype": period,
        "yyyy": yyyy,
        "ddd": ddd,
        "yyyy+1": yyyy1,
        "ddd+1": ddd1,
    }
    url = search_url
    for key, value in replacments.items():
        url = url.replace(f"[{key}]", value)
    if sitecodes:
        url += search_url_sitecodes.replace("[sssss]", ",".join(sitecodes))
    if debug:
        print(f"Search listing from {url}")
    search_output = urllib.request.urlopen(url).read()
    return json.loads(search_output)


if __name__ == "__main__":
    main()
