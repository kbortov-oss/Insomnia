# Sleep recovery and safe removal

Insomnia changes the global `disablesleep` flag during an explicitly authorized active session. Read this before testing the app. No command in this document is run automatically by build, checks, CI, or packaging.

## End a normal active session

Choose **«Обычный»** or quit through Insomnia’s menu and wait for the restoration result. Travel may try to return to a saved Wi-Fi network during a mode transition. Timer, low-battery, and power-removal stop conditions take priority, so network return is not guaranteed to finish before normal sleep can occur.

When an earlier session was not confirmed restored, the app can show **«Восстановить обычный сон…»** at the next launch. That recovery action asks for administrator authorization and explicitly warns that it clears a global flag, including one another utility might now be relying on.

## Read the current flag

For manual diagnosis, the following is read-only:

```sh
pmset -g | grep disablesleep
```

The app also reads the kernel’s `IOPMrootDomain` flag. An absent or unreadable result is not proof of recovery. A cleared sleep-disable flag removes Insomnia’s global prohibition; other normal macOS settings and power assertions may still keep the system awake.

## Manual reset

If a privileged session was interrupted and you have decided to remove the global sleep prohibition, the manual equivalent is:

```sh
sudo pmset -a disablesleep 0
```

This is a real system change requiring your own administrator authorization. It can affect another application using the same flag. Do not run it as a routine CI/check step or on someone else’s machine.

## Limits of the watchdog

Guardian checks for a missing parent, stale/malformed lease, deadline, power loss, low or unavailable battery, and persistent inability to read the flag. Heartbeat staleness is 15 seconds with roughly one-second polling. Recovery commands have timeouts and bounded retries; that is not a guarantee that the machine is fully restored within 15 seconds.

A forced kill of Guardian itself, system crash, power loss, or reboot can leave recovery to a later manual action. Releasing the global flag is verified against the actual flag when possible. If restoration cannot be confirmed, the interface reports a recovery requirement instead of declaring success.

## Closed-lid use

Keep the Mac on a ventilated surface. The project does not override thermal or hardware protections and does not establish that every Mac/OS combination supports the desired behavior. Recheck recovery after a macOS update or moving to another Mac. Do not place an intentionally awake closed Mac into a bag.
