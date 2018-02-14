# Copyright (C) 2018 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("//:version.bzl", "version_define_copts")

_ANDROID_COPTS = [
    "-fdata-sections",
    "-ffunction-sections",
    "-fvisibility-inlines-hidden",
    "-DANDROID",
    "-DTARGET_OS_ANDROID",
]

# This should probably all be done by fixing the toolchains...
def cc_copts():
    return version_define_copts() + select({
        "@//tools/build:linux": ["-DTARGET_OS_LINUX"],
        "@//tools/build:darwin": ["-DTARGET_OS_OSX"],
        "@//tools/build:windows": ["-DTARGET_OS_WINDOWS"],
        "@//tools/build:android-armeabi-v7a": _ANDROID_COPTS,
        "@//tools/build:android-arm64-v8a": _ANDROID_COPTS,
        "@//tools/build:android-x86": _ANDROID_COPTS,
    })

# Strip rule implementation, which invokes the fragment.cpp.strip_executable
# to strip debugging information from binaries.
def _strip_impl(ctx):
    extension = ctx.file.src.extension
    if not extension == "":
        extension = "." + extension
    if ctx.label.name.endswith(extension):
        extension = ""
    out = ctx.new_file(ctx.label.name + extension)

    flags = []
    if ctx.fragments.cpp.cpu == "k8" or ctx.fragments.cpp.cpu == "x64_windows":
        flags = ["--strip-unneeded", "-p"]
    elif ctx.fragments.cpp.cpu == "darwin_x86_64":
        flags = ["-x"]
    else:
        fail("Unhandled CPU type in strip rule: " + ctx.fragments.cpp.cpu)

    ctx.actions.run(
        executable = ctx.fragments.cpp.strip_executable,
        arguments = flags + ["-o", out.path, ctx.file.src.path],
        inputs = [ctx.file.src],
        outputs = [out],
    )
    return struct(
        files = depset([out])
    )

# Strip rule to strip debugging information from binaries. Has a single
# "src" attribute, which should point to the binary to be stripped.
strip = rule(
    _strip_impl,
    attrs = {
        "src": attr.label(
            allow_files = True,
            single_file = True,
        ),
    },
    fragments = ["cpp"],
)

# Macro to replace cc_binary rules. Creates the following targets:
#  <name>_unstripped[.<extension>] - The cc_binary linked with debug _symbols
#  <name> - The stripped cc_binary
def cc_stripped_binary(name, visibility, **kwargs):
    parts = name.rpartition(".")
    unstripped = name + "_unstripped" if parts[1] == "" else parts[0] + "_unstripped." + parts[2]
    native.cc_binary(
        name = unstripped,
        **kwargs
    )
    strip(
        name = name,
        src = unstripped,
        visibility = visibility,
    )
