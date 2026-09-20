---
id: DRAFT-11
title: ltl용 PATH 등록 (~/.local/bin)
status: Draft
assignee: []
created_date: '2026-09-20 21:41'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
lt_env_var_defs()에 export PATH="\/Users/flynn_macpro/.local/bin:\/opt/homebrew/opt/sqlite/bin:/Users/flynn_macpro/.asdf/shims:/Users/flynn_macpro/.local/bin:/Users/flynn_macpro/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/Users/flynn_macpro/.local/bin:/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin:/pkg/env/global/bin:/Library/Apple/usr/bin:/opt/podman/bin:/Applications/iTerm.app/Contents/Resources/utilities:/Users/flynn_macpro/Library/Application Support/JetBrains/Toolbox/scripts:/Users/flynn_macpro/.orbstack/bin:/opt/homebrew/opt/fzf/bin:/Users/flynn_macpro/go/bin:/usr/local/go/bin:/Applications/Docker.app/Contents/Resources/bin:/Users/flynn_macpro/.claude/plugins/cache/claude-plugins-official/clangd-lsp/1.0.0/bin" 항목 추가, 기존 detect_rc_file()/append_env_var() 그대로 재사용(새 셸 감지 로직 없음). m-23/decision-23 소속.
<!-- SECTION:DESCRIPTION:END -->
