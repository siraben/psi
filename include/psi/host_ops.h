#ifndef PSI_HOST_OPS_H
#define PSI_HOST_OPS_H

#include "psi/common.h"

/* Each VM owns one host context, reached through Lua state's extraspace.
 * psi_vm_call_agent scopes the observer and abort signal to the Lua
 * agent call; asynchronous tool progress carries an explicit tool ID. */

struct psi_session;
struct psi_vm;
struct psi_agent_observer;
struct psi_abort_signal;

/* Usage mirror for the TUI status line. Lua and the renderer access it
 * on the single main thread that owns lua_State. */
struct psi_host_usage {
    long input;
    long output;
    long cache_read;
    long cache_write;
    long total;
    long context_window;
};

/* Host tick hook.
 *
 * psi.sched calls psi.host_tick() between coroutine resumes. If a
 * host has installed a hook here, it runs one iteration of its own
 * event loop (e.g. the TUI: non-blocking getch + dispatch +
 * redraw). Non-TUI hosts leave this NULL and psi.host_tick becomes
 * a no-op. */
typedef void (*psi_host_tick_fn)(void *userdata);

struct psi_host_context {
    struct psi_session *session;
    struct psi_vm *vm;
    struct psi_agent_observer *active_observer;
    const char *active_tool_id;
    struct psi_abort_signal *abort_signal;
    struct psi_host_usage usage;
    psi_host_tick_fn tick_hook;
    void *tick_userdata;
};

#endif
