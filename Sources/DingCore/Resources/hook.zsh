# ding shell hook for zsh
# Installed by: ding install-hook
# Remove with: ding uninstall-hook

__ding_threshold=${DING_THRESHOLD:-30}
__ding_cmd_start=0
__ding_last_cmd=""

__ding_preexec() {
    __ding_cmd_start=$(date +%s)
    __ding_last_cmd="$1"
}

__ding_precmd() {
    local exit_code=$?
    local now
    now=$(date +%s)
    local elapsed=$(( now - __ding_cmd_start ))

    # Skip if no command was run or threshold not exceeded
    if [[ $__ding_cmd_start -eq 0 ]] || [[ $elapsed -lt $__ding_threshold ]]; then
        __ding_cmd_start=0
        return
    fi

    # Skip background commands (those ending with &)
    if [[ "$__ding_last_cmd" == *"&" ]]; then
        __ding_cmd_start=0
        return
    fi

    local status_flag="success"
    if [[ $exit_code -ne 0 ]]; then
        status_flag="failure"
    fi

    # Send notification (non-blocking, ignore errors)
    ding notify "${__ding_last_cmd}" --status "$status_flag" --title "ding" 2>/dev/null &
    disown

    __ding_cmd_start=0
}

# Register hooks (avoid duplicate registration)
if [[ -z "${__ding_hooks_loaded:-}" ]]; then
    autoload -Uz add-zsh-hook
    add-zsh-hook preexec __ding_preexec
    add-zsh-hook precmd __ding_precmd
    __ding_hooks_loaded=1
fi
