#if defined _loadmatch_included_
#endinput
#endif
#define _loadmatch_included_

/**
 * Gets the current match id and copies it into an output buffer
 *
 * @param output			Buffer to copy match id into.
 * @error 					Match id is not set.
 * @noreturn				
 */
native void GetCurrentMatchId(const char[] output);