#   PlatformIO pre-build script.
#
#   Increments a persistent build serial number and (re)generates
#   include/version.h with the current firmware version string.
#
#   The major version prefix is taken from the project option
#   `custom_major_build_number` in platformio.ini (e.g. "v1.2.").

import datetime
import os

Import("env")

PROJECT_DIR = env["PROJECT_DIR"]
BUILD_NUMBER_FILE = os.path.join(PROJECT_DIR, "buildserialnumber")
VERSION_HEADER = os.path.join(PROJECT_DIR, "include", "version.h")

try:
    major = env.GetProjectOption("custom_major_build_number")
except Exception:
    major = "v1.0."


def read_build_number():
    try:
        with open(BUILD_NUMBER_FILE, "r") as f:
            return int(f.read().strip())
    except (IOError, ValueError):
        return 0


def write_build_number(value):
    with open(BUILD_NUMBER_FILE, "w") as f:
        f.write(str(value))


build_number = read_build_number() + 1
write_build_number(build_number)

timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")
firmware_version = "{0}{1} - {2}".format(major, build_number, timestamp)
firmware_version_short = "{0}{1}".format(major, build_number)

header = """
///////////////////////////////////////////////////////////////
//
//   WARNING: This file is generated automatically,
//   all changes will be lost.
//
///////////////////////////////////////////////////////////////

#ifndef BUILD_NUMBER
  #define BUILD_NUMBER "{build_number}"
#endif
#ifndef FIRMWARE_VERSION
  #define FIRMWARE_VERSION "{firmware_version}"
#endif
#ifndef FIRMWARE_VERSION_SHORT
  #define FIRMWARE_VERSION_SHORT "{firmware_version_short}"
#endif
""".format(
    build_number=build_number,
    firmware_version=firmware_version,
    firmware_version_short=firmware_version_short,
)

os.makedirs(os.path.dirname(VERSION_HEADER), exist_ok=True)
with open(VERSION_HEADER, "w") as f:
    f.write(header)

print("Build number: {0} -> {1}".format(build_number, firmware_version_short))
