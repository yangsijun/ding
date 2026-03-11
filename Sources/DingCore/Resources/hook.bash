# ding shell hook for bash
# Installed by: ding install-hook
# Remove with: ding uninstall-hook

__ding_threshold=${DING_THRESHOLD:-30}
__ding_cmd_start=0
__ding_last_cmd=""

__ding_debug() {
    if [[ "$BASH_COMMAND" != "__ding_precmd"* ]] && [[ "$BASH_COMMAND" != "PROMPT_COMMAND"* ]]; then
        __ding_cmd_start=$(date +%s)
        __ding_last_cmd="$BASH_COMMAND"
    fi
}

__ding_precmd() {
    local exit_code=$?
    local now
    now=$(date +%s)
    local elapsed=$(( now - __ding_cmd_start ))

    if [[ $__ding_cmd_start -eq 0 ]] || [[ $elapsed -lt $__ding_threshold ]]; then
        __ding_cmd_start=0
        return
    fi

    local status_flag="success"
    if [[ $exit_code -ne 0 ]]; then
        status_flag="failure"
    fi

    ding notify "${__ding_last_cmd}" --status "$status_flag" --title "ding" 2>/dev/null &
    disown

    __ding_cmd_start=0
}

# Register hooks (avoid duplicate registration)
if [[ -z "${__ding_hooks_loaded:-}" ]]; then
    trap '__ding_debug' DEBUG
    PROMPT_COMMAND="__ding_precmd${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
    __ding_hooks_loaded=1
fi
