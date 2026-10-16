# -*- coding: utf-8 -*-
"""字面量一致性校验：关键契约字符串必须同时出现在（原包字符串表）与（复刻源码）中。

用法：python verify/verify_literals.py
"""
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STRINGS = os.path.join(ROOT, "SPEC", "assets", "strings_full.txt")

REQUIRED = [
    # 远端契约
    "https://bctwtbuvphdwbnlbprav.supabase.co",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjdHd0YnV2cGhkd2JubGJwcmF2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk3NTU5NjYsImV4cCI6MjA4NTMzMTk2Nn0.Mw4MkBJAnofnDm5Ylxe04pgjsQsloPSbzDNivBdVK-M",
    "/rest/v1/risk_control_config?id=eq.1&select=feature_flags,log_switches,max_heartbeat_fail_count,updated_at",
    "/rest/v1/heartbeats?on_conflict=anonymous_id",
    "resolution=merge-duplicates,return=minimal",
    "CodexApp/1.0",
    "CodexRemoteHeartbeatFailureLimit",
    "Codex heartbeat failed count=%ld/%ld",
    # codex CLI 契约
    "model_providers.custom={ name=\"%@\", base_url=\"%@\", env_key=\"CODEX_CUSTOM_API_KEY\", wire_api=\"responses\", requires_openai_auth=false, supports_standalone_web_search=true }",
    "model_provider=\"custom\"",
    "features.code_mode=true",
    "features.standalone_web_search=true",
    "web_search=\"live\"",
    "model_catalog_json=%@",
    "model_context_window=%lu",
    "log_dir=\"%@\"",
    "developer_instructions=%@",
    "allow_login_shell=false",
    "app-server",
    "--stdio",
    "exec",
    "--json",
    "--skip-git-repo-check",
    "--dangerously-bypass-approvals-and-sandbox",
    "--device-auth",
    "--with-api-key",
    "--with-access-token",
    # 凭据
    "CodexApp.CustomProvider",
    "APIKey",
    "CodexApp/Provider",
    ".api-key-",
    "provider credential save failed code=%ld",
    "provider credential read failed code=%ld",
    "legacy provider credential cleanup failed",
    # 运行时/更新
    "runtime-manifest.json",
    "https://gh-proxy.org/",
    "https://ghproxy.net/",
    "SHA256SUMS",
    "https://models.dev/catalog.json",
    "https://api.frankfurter.dev/v2/rate/usd/cny",
    "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json",
    "https://openrouter.ai/api/v1/models",
    "CARuntimeManifestURL",
    "archive_sha256",
    # 内部桥/环境
    "127.0.0.1:27018/mcp",
    "rmcp::transport::worker",
    "Transport channel closed",
    "forkless-posix_spawn",
    "SHELL_OK",
    "DOCS_READ",
    "DOCS_WRITE",
    "media services reset; rebuilding silent audio",
    "group.wiki.qaq.codexapp",
    "wiki.qaq.codexapp",
]


def collect_sources():
    blobs = []
    for sub in ("MTAgent/Sources", "MTShareExtension/Sources", "MTAgent", "MTShareExtension"):
        d = os.path.join(ROOT, sub)
        if not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            if f.endswith((".m", ".h", ".plist")):
                blobs.append(open(os.path.join(d, f), encoding="utf-8", errors="replace").read())
    return "\n".join(blobs)


def main():
    original = open(STRINGS, encoding="utf-8", errors="replace").read()
    replica = collect_sources()
    missing_in_replica, missing_in_original = [], []
    for literal in REQUIRED:
        in_orig = literal in original
        # 源码里可能以转义形式书写（@"... \"%@\" ..."），两种形式都算命中
        in_repl = (literal in replica) or (literal.replace('"', '\\"') in replica)
        if not in_repl:
            missing_in_replica.append(literal)
        if not in_orig:
            missing_in_original.append(literal)

    print("关键契约字面量: %d 条" % len(REQUIRED))
    print("  - 出现在原包字符串表: %d" % (len(REQUIRED) - len(missing_in_original)))
    print("  - 出现在复刻源码  : %d" % (len(REQUIRED) - len(missing_in_replica)))
    if missing_in_replica:
        print("\n[缺口] 复刻源码缺少以下字面量 (%d):" % len(missing_in_replica))
        for x in missing_in_replica:
            print("    - %s" % (x[:120]))
    if missing_in_original:
        print("\n[注意] 原包字符串表未见到以下字面量 (%d)（可能是拼接产生，需人工确认）:" % len(missing_in_original))
        for x in missing_in_original:
            print("    - %s" % (x[:120]))
    if not missing_in_replica and not missing_in_original:
        print("\n全部通过：关键契约字面量在原包与复刻源码中一一对应。")
    return 1 if (missing_in_replica or missing_in_original) else 0


if __name__ == "__main__":
    sys.exit(main())
