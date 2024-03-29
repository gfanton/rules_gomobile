load("@bazel_skylib//lib:paths.bzl", "paths")
load("@co_znly_rules_gomobile//:common.bzl", "slug")
load("@co_znly_rules_gomobile//:gobind_library.bzl", "gobind_library")
load("@co_znly_rules_gomobile//:providers.bzl", "GoBindInfo")
load("@co_znly_rules_gomobile//platform:transitions.bzl", "go_platform_transition")
load("@io_bazel_rules_go//go:def.bzl", "go_binary", "go_path")

_MODULE_MAP_TPL = """\
module {name} {{
    export *
{headers}
}}
"""

def _normalize_module_name(label):
    parts = [
        s
        for s in [
            label.workspace_name,
            label.package,
            label.name,
        ]
        if s
    ]
    return "_".join(parts).replace("/", "_").replace(".", "_")

def _create_module_map(ctx, gobind_info):
    module_name = _normalize_module_name(ctx.label)
    headers = "\n".join([
        "header \"./%s\"" % paths.relativize(hdr.short_path, ctx.label.package)
        for hdr in gobind_info.objc
    ])
    f = ctx.actions.declare_file("module.modulemap")
    ctx.actions.write(f, _MODULE_MAP_TPL.format(
        name = module_name,
        headers = headers,
    ))
    return f

def _gobind_ios_artifacts_impl(ctx):
    gobind_info = ctx.attr.gobind[GoBindInfo]
    return [
        OutputGroupInfo(
            hdrs = depset(gobind_info.objc),
        ),
        apple_common.new_objc_provider(
            header = depset(gobind_info.objc),
            imported_library = depset(ctx.files.binary),
            force_load_library = depset(ctx.files.binary),
            include = depset(["."]),
            module_map = depset([_create_module_map(ctx, gobind_info)]),
        ),
    ]

gobind_ios_artifacts = rule(
    _gobind_ios_artifacts_impl,
    attrs = {
        "binary": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "gobind": attr.label(
            mandatory = True,
            providers = [GoBindInfo],
        ),
        "_whitelist_function_transition": attr.label(
            default = "@bazel_tools//tools/whitelists/function_transition_whitelist",
        ),
    },
    cfg = go_platform_transition,
)

def gobind_objc(name, deps, objc_prefix, tags, **kwargs):
    gopath_name = slug(name, "objc", "gopath")
    gobind_name = slug(name, "objc", "gobind")
    binary_name = slug(name, "objc", "binary")
    artifacts_name = slug(name, "objc", "artifacts")
    objc_library_name = slug(name, "objc")
    objc_library_hdrs_name = slug(objc_library_name, "hdrs")

    go_path(
        name = gopath_name,
        mode = "link",
        include_pkg = True,
        include_transitive = False,
        linkmode = "c-archive",
        deps = deps + [
            "@org_golang_x_mobile//bind:go_default_library",
            "@org_golang_x_mobile//bind/objc:go_default_library",
        ],
    )
    gobind_library(
        name = gobind_name,
        go_path = gopath_name,
        lang = ["go", "objc"],
        objc_prefix = objc_prefix,
        copts = [
            "-xobjective-c",
            "-fmodules",
            "-fobjc-arc",
            "-D__GOBIND_DARWIN__",
        ],
        go_tags = tags + ["ios"],
        deps = deps,
    )
    copts = kwargs.pop("copts", []) + [
        "-xobjective-c",
        "-fmodules",
        "-fobjc-arc",
        "-D__GOBIND_DARWIN__",
    ]
    go_binary(
        name = binary_name,
        embed = [gobind_name],
        out = binary_name + ".a",
        deps = deps + [
            "@org_golang_x_mobile//bind/java:go_default_library",
            "@org_golang_x_mobile//bind/seq:go_default_library",
        ],
        copts = copts,
        pure = "off",
        linkmode = "c-archive",
        **kwargs
    )
    gobind_ios_artifacts(
        name = objc_library_name,
        gobind = gobind_name,
        binary = binary_name,
        visibility = ["//visibility:public"],
    )
    native.filegroup(
        name = objc_library_hdrs_name,
        srcs = [objc_library_name],
        output_group = "hdrs",
        visibility = ["//visibility:public"],
    )
