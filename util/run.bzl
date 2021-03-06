# Copyright 2017 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Rules to run a command inside a container, and either commit the result
to new container image, or extract specified targets to a directory on
the host machine.
"""

load(
    "@io_bazel_rules_docker//container:bundle.bzl",
    "container_bundle",
)

def _extract_impl(ctx, name = "", image = None, commands = None, docker_run_flags = None, extract_file = "", output_file = "", script_file = ""):
    """Implementation for the container_run_and_extract rule.

    This rule runs a set of commands in a given image, waits for the commands
    to finish, and then extracts a given file from the container to the
    bazel-out directory.

    Args:
        ctx: The bazel rule context
        name: String, overrides ctx.label.name
        image: File, overrides ctx.file.image_tar
        commands: String list, overrides ctx.attr.commands
        docker_run_flags: String list, overrides ctx.attr.docker_run_flags
        extract_file: File, overrides ctx.outputs.out
    """
    name = name or ctx.label.name
    image = image or ctx.file.image
    commands = commands or ctx.attr.commands
    docker_run_flags = docker_run_flags or ctx.attr.docker_run_flags
    extract_file = extract_file or ctx.attr.extract_file
    output_file = output_file or ctx.outputs.out
    script = script_file or ctx.outputs.script

    # Generate a shell script to execute the run statement
    ctx.actions.expand_template(
        template = ctx.file._extract_tpl,
        output = script,
        substitutions = {
            "%{image_tar}": image.path,
            "%{commands}": _process_commands(commands),
            "%{docker_run_flags}": " ".join(docker_run_flags),
            "%{extract_file}": extract_file,
            "%{output}": output_file.path,
            "%{image_id_extractor_path}": ctx.file._image_id_extractor.path,
        },
        is_executable = True,
    )

    ctx.actions.run(
        outputs = [output_file],
        inputs = [image, ctx.file._image_id_extractor],
        executable = script,
    )

    return struct()

_extract_attrs = {
    "image": attr.label(
        executable = True,
        allow_files = True,
        mandatory = True,
        single_file = True,
        cfg = "target",
    ),
    "commands": attr.string_list(
        doc = "commands to run",
        mandatory = True,
        non_empty = True,
    ),
    "docker_run_flags": attr.string_list(
        doc = "Extra flags to pass to the docker run command",
        mandatory = False,
    ),
    "extract_file": attr.string(
        doc = "path to file to extract from container",
        mandatory = True,
    ),
    "_extract_tpl": attr.label(
        default = Label("//util:extract.sh.tpl"),
        allow_files = True,
        single_file = True,
    ),
    "_image_id_extractor": attr.label(
        default = "@io_bazel_rules_docker//contrib:extract_image_id.py",
        allow_files = True,
        single_file = True,
    ),
}

_extract_outputs = {
    "out": "%{name}%{extract_file}",
    "script": "%{name}.build",
}

# Export container_run_and_extract rule for other bazel rules to depend on.
extract = struct(
    attrs = _extract_attrs,
    outputs = _extract_outputs,
    implementation = _extract_impl,
)

"""
This rule runs a set of commands in a given image, waits for the commands
    to finish, and then extracts a given file from the container to the
    bazel-out directory.

    name: A unique name for this rule.
    image: The image to run the commands in.
    commands: A list of commands to run (sequentially) in the container.
    extract_file: The file to extract from the container.
"""
container_run_and_extract = rule(
    attrs = _extract_attrs,
    outputs = _extract_outputs,
    implementation = _extract_impl,
)

def _commit_impl(
        ctx,
        name = None,
        image = None,
        commands = None,
        output_image_tar = None):
    """Implementation for the container_run_and_commit rule.

    This rule runs a set of commands in a given image, waits for the commands
    to finish, and then commits the container to a new image.

    Args:
        ctx: The bazel rule context
        image: The input image tarball
        image_runfiles: Any runfiles that were generated along with the input
                        image
        commands: The commands to run in the input imnage container
        output_image_tar: The output image obtained as a result of running
                          the commands on the input image
    """

    name = name or ctx.attr.name
    image = image or ctx.file.image
    commands = commands or ctx.attr.commands
    script = ctx.new_file(name + ".build")
    output_image_tar = output_image_tar or ctx.outputs.out

    # Generate a shell script to execute the run statement
    ctx.actions.expand_template(
        template = ctx.file._run_tpl,
        output = script,
        substitutions = {
            "%{util_script}": ctx.file._image_utils.path,
            "%{output_image}": "bazel/%s:%s" % (
                ctx.label.package or "default",
                name,
            ),
            "%{image_tar}": image.path,
            "%{commands}": _process_commands(commands),
            "%{output_tar}": output_image_tar.path,
            "%{image_id_extractor_path}": ctx.file._image_id_extractor.path,
        },
        is_executable = True,
    )

    runfiles = [image, ctx.file._image_utils, ctx.file._image_id_extractor]

    ctx.actions.run(
        outputs = [output_image_tar],
        inputs = runfiles,
        executable = script,
    )

    return struct()

_commit_attrs = {
    "image": attr.label(
        allow_files = True,
        mandatory = True,
        single_file = True,
        cfg = "target",
    ),
    "commands": attr.string_list(
        doc = "commands to run",
        mandatory = True,
        non_empty = True,
    ),
    "_run_tpl": attr.label(
        default = Label("//util:commit.sh.tpl"),
        allow_files = True,
        single_file = True,
    ),
    "_image_utils": attr.label(
        default = "//util:image_util.sh",
        allow_files = True,
        single_file = True,
    ),
    "_image_id_extractor": attr.label(
        default = "@io_bazel_rules_docker//contrib:extract_image_id.py",
        allow_files = True,
        single_file = True,
    ),
}
_commit_outputs = {
    "out": "%{name}_commit.tar",
}

"""Runs commands in a container and commits the container to a new image.

This rule runs a set of commands in a given image, waits for the commands
to finish, and then commits the container to a new image.


Args:
    image: Tarball of image to run commands on.
    commands: A list of commands to run (sequentially) in the container.
    _run_tpl: Template for generated script to run docker commands.
    _image_id_extractor: A script to extract a tarball's image's id
"""
container_run_and_commit = rule(
    attrs = _commit_attrs,
    executable = False,
    outputs = _commit_outputs,
    implementation = _commit_impl,
)

# Export container_run_and_commit rule for other bazel rules to depend on.
commit = struct(
    attrs = _commit_attrs,
    outputs = _commit_outputs,
    implementation = _commit_impl,
)

def _process_commands(command_list):
    # Use the $ to allow escape characters in string
    return 'sh -c $\"{0}\"'.format(" && ".join(command_list))
