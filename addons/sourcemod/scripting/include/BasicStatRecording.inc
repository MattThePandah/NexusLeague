/*
**
*/
#if defined _BasicStatRecording_included
 #endinput
#endif
#define _BasicStatRecording_included

forward void OnKill(int killer, int victim, bool headshot);
forward void OnDeath(int victim, int killer, int assister);
forward void OnAssist(int assister, int victim);
forward void OnRoundWon(int team);
forward void OnPlayerRoundWon(int client, int team, int enemyRemaining);
forward void OnRoundLost(int team);
forward void OnPlayerRoundLost(int client, int team, int enemyRemaining);
forward void OnShotFired(int client, int shots, const char[] weaponName);
forward void OnPlayerHit(int victim, int attacker, int damage);
forward void OnHeadShot(int victim, int attacker);



/*
#if !defined REQUIRE_PLUGIN
public __pl_INTERFACE_SetNTVOptional()
{
	MarkNativeAsOptional("");
}
#endif
*/

public SharedPlugin __pl_BasicStatRecording =
{
	name = "Basic Player Stats",
	file = "BasicStatRecording.smx",
	#if defined REQUIRE_PLUGIN
	required = 1,
	#else
	required = 0,
	#endif
};
