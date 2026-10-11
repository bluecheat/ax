#!/usr/bin/env bash
# .ax/scripts/bash/lib/shellscan.sh — 셸 명령 스캔 — goax_shell_scan (python3 shlex). pre-bash 게이트가 써요
# common.sh 가 source 해요. 직접 source 하지 않아요.
# shellcheck disable=SC2034  # 여기서 정의한 변수는 common.sh 를 source 한 스크립트가 써요

# ─── 셸 명령 스캔 — 따옴표·세미콜론·heredoc 을 셸처럼 읽어요 ─────────────
# goax_shell_scan <bypass|destructive> <project-root> [cwd]   (명령은 stdin)
#   출력: 걸린 것마다 한 줄 `<사유>`. 없으면 빈 출력. python3 가 없으면 exit 3 (호출자가 degrade).
#   bypass       에이전트가 git 훅을 끄는 형태 — `--no-verify` · `git commit -n` · `-c core.hooksPath=` ·
#                `git config core.hooksPath <값>` · `HUSKY=0`/`LEFTHOOK=0`
#   destructive  프로젝트 안에서 되돌리기 어려운 형태 — 재귀 rm(재생성 가능한 build·node_modules 등 제외,
#                프로젝트 밖 경로 제외) · `find -delete` · `git clean -f` · `git checkout -- <경로>`/`.`/`-f` ·
#                `git restore`(작업 트리) · `git reset --hard` · `git stash drop|clear` · `git branch -D`
#   정규식 한 줄로는 `git commit -m "fix -n handling"` 의 `-n` 을 플래그로 읽어요 — 그래서 토큰 단위로 봐요.
#   `sh -c '…'`·`bash -lc "…"` 안쪽도 한 번 더 읽고, heredoc 본문은 명령이 아니라 버려요.
#   값이 변수(`$X`)인 경로는 판단하지 않아요 — 사고 방지용 안전망이지 보안 경계가 아니에요.
goax_shell_scan() {
    local mode="${1:-}" root="${2:-}" cwd="${3:-}" cmd extra
    cmd=$(cat)
    goax_py_ok || return 3
    [ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$(pwd)"
    extra=$(goax_yaml_list "$root/.ax/config.yml" regenerable_paths 2>/dev/null || true)
    # 명령은 argv 로 넘겨요 — python 프로그램 자체가 heredoc(stdin) 으로 들어가서 stdin 은 비어 있어요.
    # python 이 도중에 죽으면(exit ≠ 0) 판정을 못 한 거예요 — 빈 결과(= 통과)가 아니라 3 으로 돌려서 호출자가 degrade 해요.
    ( cd "$cwd" 2>/dev/null && python3 - "$mode" "$root" "$cmd" "$extra" <<'PYSCAN'
import os, re, shlex, sys
mode = sys.argv[1]
root = os.path.realpath(sys.argv[2]) if sys.argv[2] else ""
raw = sys.argv[3]

def strip_comment(line, q):
    # 따옴표 밖, 낱말 첫머리의 `#` 부터 줄 끝이 주석이에요 (셸 규칙). `${#a}` 나 `a#b` 는 주석이 아니에요.
    # shlex 의 commenters 는 이걸 구분 못 하고 줄바꿈을 합친 뒤라 **명령 나머지 전부**를 먹어서 끄고 여기서 해요.
    # q 는 여러 줄에 걸친 따옴표 상태 (커밋 메시지 본문 같은 것).
    out, prev = [], " "
    i = 0
    while i < len(line):
        c = line[i]
        if q:
            if c == "\\" and q == "\"" and i + 1 < len(line):
                out.append(line[i:i+2]); i += 2; prev = "x"; continue
            if c == q:
                q = None
        elif c in "'\"":
            q = c
        elif c == "\\" and i + 1 < len(line):
            out.append(line[i:i+2]); i += 2; prev = "x"; continue
        elif c == "#" and (prev.isspace() or prev in ";&|("):
            break
        out.append(c); prev = c; i += 1
    return "".join(out), q

def strip_heredocs(s):
    out, delims, q = [], [], None
    for line in s.split("\n"):
        if delims:
            if line.strip().lstrip("\t") == delims[0]:
                delims.pop(0)
            continue
        line, q = strip_comment(line, q)
        out.append(line)
        # `<<<` 는 here-string 이라 끝 표지가 없어요 — heredoc 으로 읽으면 뒤 줄을 전부 버려요
        for m in re.finditer(r"(?<!<)<<(?!<)-?[ \t]*([\"']?)([A-Za-z_][A-Za-z0-9_]*)\1", line):
            delims.append(m.group(2))
    return "\n".join(out)

PUNCT = set(";&|()")
def segments(s):
    s = strip_heredocs(s).replace("\n", " ; ")
    lx = shlex.shlex(s, posix=True, punctuation_chars=";&|()")
    lx.whitespace_split = True
    lx.commenters = ""
    try:
        toks = list(lx)
    except ValueError:
        return None
    segs, cur = [], []
    for t in toks:
        if t and all(c in PUNCT for c in t):
            segs.append(cur); cur = []
        else:
            cur.append(t)
    segs.append(cur)
    return [x for x in segs if x]

WRAP = {"sudo", "env", "command", "exec", "nohup", "time", "nice", "xargs", "caffeinate"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}
def unwrap(seg):
    env, i = {}, 0
    while i < len(seg):
        t = seg[i]
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", t)
        if m:
            env[m.group(1)] = m.group(2); i += 1; continue
        b = os.path.basename(t)
        if b in WRAP:
            i += 1
            while i < len(seg) and seg[i].startswith("-"):
                if b == "sudo" and seg[i] in ("-u", "-g", "-C", "-D", "-h", "-p", "-U"):
                    i += 1
                elif b == "xargs" and seg[i] in ("-n", "-I", "-L", "-P", "-s", "-d", "-E", "-a"):
                    i += 1
                i += 1
            continue
        break
    return env, seg[i:]

def inner_script(args):
    for k, a in enumerate(args):
        if a.startswith("-") and not a.startswith("--") and "c" in a[1:]:
            return args[k + 1] if k + 1 < len(args) else None
    return None

GIT_C = [None]   # 마지막 git_split 이 본 `-C <경로>`
GIT_OPT_NEXT = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"}
def git_split(args):
    cfg, i = [], 0
    GIT_C[0] = None
    while i < len(args):
        a = args[i]
        if a == "-C" and i + 1 < len(args):
            GIT_C[0] = args[i + 1]; i += 2; continue
        if a == "-c" or a == "--config-env":
            cfg.append(args[i + 1] if i + 1 < len(args) else ""); i += 2; continue
        if a.startswith("-c") and len(a) > 2 and not a.startswith("--"):
            cfg.append(a[2:]); i += 1; continue
        if a.startswith("--config-env="):
            cfg.append(a.split("=", 1)[1]); i += 1; continue
        if a in GIT_OPT_NEXT:
            i += 2; continue
        if a.startswith("-"):
            i += 1; continue
        return cfg, a, args[i + 1:]
    return cfg, None, []

NOVERIFY_SUBS = {"commit", "push", "merge", "cherry-pick", "rebase", "am", "pull"}
ARG_NEXT = {"-m", "-F", "-C", "-c", "-t", "-o", "--message", "--file", "--author", "--date",
            "--reuse-message", "--reedit-message", "--fixup", "--squash", "--template",
            "--trailer", "--cleanup", "--push-option", "--pathspec-from-file", "--strategy",
            "--strategy-option", "-s", "-X", "--onto", "--exec", "-x"}
COMMIT_ARG_SHORT = set("mFCctSu")

def hook_env_reason(env, git_cmd):
    # 훅 매니저마다 끄는 변수가 달라요 — husky(HUSKY=0, v4 HUSKY_SKIP_HOOKS) · lefthook(LEFTHOOK=0, LEFTHOOK_EXCLUDE) ·
    # pre-commit 프레임워크(SKIP=<훅id>). SKIP 은 흔한 이름이라 git 명령 앞에 붙었거나 export 될 때만 봐요.
    for k in ("HUSKY", "LEFTHOOK"):
        if env.get(k, "").lower() in ("0", "false"):
            return "%s=%s (프로젝트 git 훅 끄기)" % (k, env[k])
    for k in ("HUSKY_SKIP_HOOKS", "LEFTHOOK_EXCLUDE") + (("SKIP",) if git_cmd else ()):
        v = env.get(k, "")
        if v and v.lower() not in ("0", "false"):
            return "%s=%s (프로젝트 git 훅 건너뛰기)" % (k, v)
    return None

def bypass_seg(seg, depth):
    env, seg = unwrap(seg)
    if seg and seg[0] in ("export", "declare", "typeset"):
        ex = {}
        for a in seg[1:]:
            m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", a)
            if m:
                ex[m.group(1)] = m.group(2)
        return hook_env_reason(ex, True)
    r = hook_env_reason(env, bool(seg) and os.path.basename(seg[0]) == "git")
    if r:
        return r
    if not seg:
        return None
    b = os.path.basename(seg[0])
    if b in SHELLS and depth < 2:
        sc = inner_script(seg[1:])
        return scan(sc, depth + 1) if sc else None
    if b != "git":
        return None
    cfg, sub, rest = git_split(seg[1:])
    for c in cfg:
        if c.lower().startswith("core.hookspath"):
            return "git -c %s (훅 경로 바꿔치기)" % c
    if sub == "config":
        low = [a.lower() for a in rest]
        if "core.hookspath" in low:
            k = low.index("core.hookspath")
            vals = [a for a in rest[k + 1:] if not a.startswith("-")]
            if vals:
                return "git config core.hooksPath %s (훅 경로 바꿔치기)" % vals[0]
        return None
    if sub not in NOVERIFY_SUBS:
        return None
    j = 0
    while j < len(rest):
        a = rest[j]
        if a == "--":
            break
        if a == "--no-verify":
            return "git %s --no-verify" % sub
        if a in ARG_NEXT:
            j += 2; continue
        if sub == "commit" and re.match(r"^-[A-Za-z]+$", a):
            for ch in a[1:]:
                if ch == "n":
                    return "git commit -n (--no-verify 의 짧은 형태)"
                if ch in COMMIT_ARG_SHORT:
                    break
        j += 1
    return None

# 지워도 도구가 다시 만드는 디렉토리 — 스택을 가정하지 않으려고 여러 생태계의 흔한 이름을 **기본값**으로만 둬요.
# 프로젝트는 .ax/config.yml sensors.regenerable_paths 글롭으로 넓혀요 (argv[4], 줄바꿈 구분).
REGEN = {
    # JS/TS
    "node_modules", "bower_components", ".pnpm-store", ".next", ".nuxt", ".output", ".svelte-kit", ".angular",
    ".expo", ".parcel-cache", ".turbo", ".vercel", ".netlify", ".docusaurus", "storybook-static", ".nyc_output",
    # JVM · 네이티브 · 모바일
    "build", "out", "target", ".gradle", ".kotlin", ".build", "DerivedData", "Pods", ".dart_tool", ".cxx",
    # Python
    "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox", ".nox", ".venv", "venv", ".eggs",
    # 공통
    "dist", "coverage", ".cache", ".terraform", ".serverless", ".aws-sam", ".session",
}
REGEN_SUFFIX = (".egg-info",)
REGEN_PREFIX = ("cmake-build-",)
def glob_rx(g):
    out, i, n = [], 0, len(g)
    while i < n:
        c = g[i]
        if c == "*":
            if i + 1 < n and g[i + 1] == "*":
                out.append(".*"); i += 2
                if i < n and g[i] == "/": i += 1
                continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        elif c in ".+(){}[]|^$\\":
            out.append("\\" + c)
        else:
            out.append(c)
        i += 1
    return re.compile("^" + "".join(out) + "(/.*)?$")
EXTRA = [glob_rx(g.strip().rstrip("/")) for g in (sys.argv[4] if len(sys.argv) > 4 else "").split("\n") if g.strip()]
def regenerable(parts):
    if any(x in REGEN or x.endswith(REGEN_SUFFIX) or x.startswith(REGEN_PREFIX) for x in parts):
        return True
    rel = "/".join(parts)
    return any(rx.match(rel) for rx in EXTRA)

CWD = [os.getcwd()]   # `cd x && rm -rf ../y` 처럼 앞 세그먼트의 cd 를 따라가요
def risky_path(t):
    if "$" in t or "`" in t:
        return False
    p = os.path.expanduser(t)
    ab = os.path.realpath(os.path.join(CWD[0], p))
    if root and not (ab == root or ab.startswith(root + os.sep)):
        return False
    rel = os.path.relpath(ab, root) if root else ab
    parts = [x for x in rel.split(os.sep) if x not in ("", ".")]
    if regenerable(parts):
        return False
    return True

def destructive_seg(seg, depth, piped_in):
    env, seg = unwrap(seg)
    if not seg:
        return None
    b = os.path.basename(seg[0])
    args = seg[1:]
    if b == "cd":
        dest = args[0] if args else os.path.expanduser("~")
        if "$" not in dest and "`" not in dest and dest != "-":
            CWD[0] = os.path.realpath(os.path.join(CWD[0], os.path.expanduser(dest)))
        return None
    if b in SHELLS and depth < 2:
        sc = inner_script(args)
        return scan(sc, depth + 1) if sc else None
    if b == "rm":
        rec, targets, opts, skip = False, [], True, False
        for a in args:
            if skip:
                skip = False; continue
            if re.match(r"^[0-9]*(>|>>|<|&>|>&)$", a):      # `> out.log` — 다음 토큰은 리다이렉션 대상
                skip = True; continue
            if ">" in a or "<" in a:                         # `2>/dev/null`, `2>` (`2>&1` 의 앞 조각)
                continue
            if opts and a == "--":
                opts = False; continue
            if opts and a.startswith("--"):
                rec = rec or a == "--recursive"; continue
            if opts and a.startswith("-") and len(a) > 1:
                rec = rec or "r" in a[1:] or "R" in a[1:]; continue
            targets.append(a)
        if not rec:
            return None
        if not targets:
            return "재귀 rm — 대상이 파이프로 들어와 알 수 없어요" if piped_in else None
        hit = [t for t in targets if risky_path(t)]
        return "재귀 rm: %s" % " ".join(hit) if hit else None
    if b == "find" and ("-delete" in args or any(a == "-exec" and k + 1 < len(args) and os.path.basename(args[k + 1]) == "rm"
                                                 for k, a in enumerate(args))):
        starts = []
        for a in args:
            if a.startswith("-") or a in ("(", "!"):
                break
            starts.append(a)
        hit = [t for t in (starts or ["."]) if risky_path(t)]
        return "find 로 대량 삭제: %s" % " ".join(hit) if hit else None
    if b != "git":
        return None
    _, sub, rest = git_split(args)
    gdir = CWD[0]
    if GIT_C[0]:
        if "$" in GIT_C[0] or "`" in GIT_C[0]:
            return None
        gdir = os.path.realpath(os.path.join(CWD[0], os.path.expanduser(GIT_C[0])))
        if root and not (gdir == root or gdir.startswith(root + os.sep)):
            return None                                  # 다른 리포 — 이 프로젝트의 일이 아니에요
    shorts = "".join(a[1:] for a in rest if re.match(r"^-[A-Za-z]+$", a))
    if sub == "clean":
        if "n" in shorts or "--dry-run" in rest:
            return None
        if "f" in shorts or "--force" in rest:
            return "git clean -f — 추적 안 되는 파일 삭제 (복구 불가)"
        return None
    if sub == "checkout":
        if "--" in rest and rest.index("--") + 1 < len(rest):
            return "git checkout -- <경로> — 작업 트리 변경 폐기"
        if "." in rest:
            return "git checkout . — 작업 트리 변경 폐기"
        if "f" in shorts or "--force" in rest:
            return "git checkout -f — 작업 트리 변경 폐기"
        # `git checkout <파일>` — `--` 없이도 실제 경로면 그 파일의 변경을 버려요 (브랜치 이름과는 경로 존재로 가려요)
        for a in rest:
            if not a.startswith("-") and os.path.exists(os.path.join(gdir, a)):
                return "git checkout <경로> — 작업 트리 변경 폐기"
        return None
    if sub == "switch" and ("f" in shorts or "--force" in rest or "--discard-changes" in rest):
        return "git switch -f — 작업 트리 변경 폐기"
    if sub == "worktree" and rest[:1] == ["remove"] and ("f" in shorts or "--force" in rest):
        return "git worktree remove --force — 워크트리의 커밋 안 된 변경 폐기"
    if sub == "restore":
        staged = "--staged" in rest or "S" in shorts
        worktree = "--worktree" in rest or "W" in shorts
        if worktree or not staged:
            return "git restore — 작업 트리 변경 폐기"
        return None
    if sub == "reset" and "--hard" in rest:
        return "git reset --hard — 커밋 안 된 변경 폐기"
    if sub == "stash" and rest and rest[0] in ("drop", "clear"):
        return "git stash %s — 스태시 삭제" % rest[0]
    if sub == "branch" and ("D" in shorts or ("--delete" in rest and ("--force" in rest or "f" in shorts))):
        return "git branch -D — 머지 안 된 브랜치 삭제"
    return None

def scan(s, depth=0):
    segs = segments(s)
    if segs is None:
        return None
    hits = []
    for k, seg in enumerate(segs):
        if mode == "bypass":
            r = bypass_seg(seg, depth)
        else:
            r = destructive_seg(seg, depth, k > 0)
        if r:
            if depth > 0:
                return r
            hits.append(r)
    return hits if depth == 0 else None

res = scan(raw)
for h in (res or []):
    print(h)
PYSCAN
    ) || return 3
    return 0
}
