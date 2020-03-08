#pragma semicolon 1

bool DEBUG = false;

#define PLUGIN_AUTHOR "PandahChan"
#define PLUGIN_VERSION "0.00"

#include "BasicStatRecording.inc"
#include "get5.inc"
#include <cstrike>
#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma newdecls required

#define STRING(%1) %1,sizeof(%1)
#define ISEMPTY(%1) (%1[0] == '\0')

char Q_INSERT_PLAYER[] = "INSERT INTO `statistics`"...
" (`steamid`,`ip`,`name`,`lastconnect`,`region`)"...
" VALUES ('%s','%s','%s',%d,'%s') ON DUPLICATE KEY UPDATE `ip`='%s', `name`='%s', `lastconnect`=%d, `region`='%s'";

char Q_UPDATE_PLAYER[] = "UPDATE `statistics` SET `ip`='%s', `name`='%s', `kills`=kills+%d, `deaths`=deaths+%d,"...
" `assists`=assists+%d, `mvps`=mvps+%d, `1v2`=1v2+%d, `1v3`=1v3+%d, `1v4`=1v4+%d, `1v5`=1v5+%d, `3k`=3k+%d, `4k`=4k+%d, `5k`=5k+%d, `shots`=shots+%d, `hits`=hits+%d, `damage`=damage+%d, `headshots`=headshots+%d, "...
"`roundswon`=roundswon+%d, `roundslost`=roundslost+%d,"...
" `wins`=wins+%d, `losses`=losses+%d, `ties`=ties+%d, "...
"`points`=points+%d, `lastconnect`=%d, `totaltime`=totaltime+%d WHERE `steamid` = '%s'";

char Q_GET_PLAYER[] = "SELECT * FROM `statistics` WHERE `steamid` = '%s'";

Database g_hThreadedDb = null;

float g_fJoinTime[MAXPLAYERS+1];

// Scrappy fix before I modify get5_endmatch
bool hasCalculated = false;

ConVar g_serverRegion;

int g_iClutchFor;
int g_iOpponents; 

methodmap QueuedQuery < StringMap
{
	public QueuedQuery(const char[] steamid64)
	{
		StringMap queryData = new StringMap();
		queryData.SetString("id", steamid64);
		
		return view_as<QueuedQuery>(queryData);
	}
	
	public int getValue(const char[] key)
	{
		int value;
		if (this.GetValue(key, value))
		{
			return value;
		}
		
		return -1;
	}
	
	public bool getString(const char[] key)
	{
		char buffer[255];
		return this.GetString(key, STRING(buffer));
	}
}

methodmap PlayerStatsTracker < StringMap
{
	//Consider making the keys the same name as db columns. Allows for easier specific insertion and update to db.
	public PlayerStatsTracker(int id)
	{
		if (!VALIDPLAYER(id) && !DEBUG)
		{
			return null;
		}
		
		StringMap playerstats = new StringMap();
		char id64[32];
		char ipaddress[32];
		char playername[32];
		char region[32];

		if (!GetClientAuthId(id, AuthId_SteamID64, STRING(id64)))
		{
			if (DEBUG)
			{
				Format(STRING(id64), "BOT_%d", id);
			}
			else
			{
				Format(STRING(id64), "INVALID_%d", id);
			}
			
		}

		GetConVarString(g_serverRegion, region, sizeof(region));

		GetClientIP(id, STRING(ipaddress));
		GetClientName(id, STRING(playername));
		playerstats.SetValue("uid", GetClientUserId(id));
		playerstats.SetString("id64", id64);
		playerstats.SetString("ip", ipaddress);
		playerstats.SetString("ign", playername);
		playerstats.SetValue("kills", 0);
		playerstats.SetValue("deaths", 0);
		playerstats.SetValue("assists", 0);
		playerstats.SetValue("mvps", 0);
		playerstats.SetValue("1v2", 0);
		playerstats.SetValue("1v3", 0);
		playerstats.SetValue("1v4", 0);
		playerstats.SetValue("1v5", 0);
		playerstats.SetValue("triplekill", 0);
		playerstats.SetValue("quadrakill", 0);
		playerstats.SetValue("pentakill", 0);
		playerstats.SetValue("roundswon", 0);
		playerstats.SetValue("roundslost", 0);
		playerstats.SetValue("matcheswon", 0);
		playerstats.SetValue("matcheslost", 0);
		playerstats.SetValue("matchestied", 0);
		playerstats.SetValue("shots", 0);
		playerstats.SetValue("hits", 0);
		playerstats.SetValue("damage", 0);
		playerstats.SetValue("headshots", 0);
		playerstats.SetValue("points", 0);
		playerstats.SetValue("lastconnect", GetTime());
		playerstats.SetValue("totaltime", 0);
		playerstats.SetString("region", region);
		
		return view_as<PlayerStatsTracker>(playerstats);
	}
	
	public bool isValidPlayer()
	{
		char id64[32];
		this.GetString("id64", STRING(id64));
		
		return !(StrContains(id64, "BOT") != -1 || StrContains(id64, "INVALID") != -1);
	}
	
	public bool isPlayersStats(int userid)
	{
		int uid = 0;
		this.GetValue("uid", uid);
		if (uid == userid)
		{
			return true;
		}
		
		return false;
	}
	
	public void setTripleKill()
	{
		this.SetValue("triplekill", 1);
	}
	
	public void setQuadraKill()
	{
		this.SetValue("quadrakill", 1);
	}
	
	public void setPentaKill()
	{
		this.SetValue("pentakill", 1);
	}

	public void setOneVTwo()
	{
		this.SetValue("1v2", 1);
	}

	public void setOneVThree()
	{
		this.SetValue("1v3", 1);
	}

	public void setOneVFour()
	{
		this.SetValue("1v4", 1);
	}

	public void setOneVFive()
	{
		this.SetValue("1v5", 1);
	}
	
	public void incrementKills()
	{
		int kills = 0;
		this.GetValue("kills", kills);
		this.SetValue("kills", ++kills);
	}
	
	public void incrementDeaths()
	{
		int deaths = 0;
		this.GetValue("deaths", deaths);
		this.SetValue("deaths", ++deaths);
	}
	
	public void incrementAssists()
	{
		int assists = 0;
		this.GetValue("assists", assists);
		this.SetValue("assists", ++assists);
	}
	
	public void incrementRoundsWon()
	{
		int roundsWon = 0;
		this.GetValue("roundswon", roundsWon);
		this.SetValue("roundswon", ++roundsWon);
	}
	
	public void incrementRoundsLost()
	{
		int roundsLost = 0;
		this.GetValue("roundslost", roundsLost);
		this.SetValue("roundslost", ++roundsLost);
	}
	
	public void incrementMatchesWon()
	{
		int matchesWon = 0;
		this.GetValue("matcheswon", matchesWon);
		this.SetValue("matcheswon", ++matchesWon);
	}
	
	public void incrementMatchesLost()
	{
		int matchesLost = 0;
		this.GetValue("matcheslost", matchesLost);
		this.SetValue("matcheslost", ++matchesLost);
	}
	
	public void incrementMatchesTied()
	{
		int matchesTied = 0;
		this.GetValue("matchestied", matchesTied);
		this.SetValue("matchestied", ++matchesTied);
	}
	
	public void incrementShots(int shotsFired)
	{
		int shots = 0;
		this.GetValue("shots", shots);
		this.SetValue("shots", shots+shotsFired);
	}

	public void incrementDamage(int damageDealt)
	{
		int damage = 0;
		this.GetValue("damage", damage);
		this.SetValue("damage", damage+damageDealt);
	}
	
	public void incrementHits()
	{
		int hits = 0;
		this.GetValue("hits", hits);
		this.SetValue("hits", ++hits);
	}
	
	public void incrementHeadshots()
	{
		int headshots = 0;
		this.GetValue("headshots", headshots);
		this.SetValue("headshots", ++headshots);
	}

	public void incrementMVPs()
	{
		int mvps = 0;
		this.GetValue("mvps", mvps);
		this.SetValue("mvps", ++mvps);
	}
	
	public void addPoints(int pointsToAdd)
	{
		int points = 0;
		this.GetValue("points", points);
		this.SetValue("points", points + pointsToAdd);
	}
	
	public void resetStats()
	{
		this.SetValue("kills", 0);
		this.SetValue("deaths", 0);
		this.SetValue("assists", 0);
		this.SetValue("mvps", 0);
		this.SetValue("1v2", 0);
		this.SetValue("1v3", 0);
		this.SetValue("1v4", 0);
		this.SetValue("1v5", 0);
		this.SetValue("triplekill", 0);
		this.SetValue("quadrakill", 0);
		this.SetValue("pentakill", 0);
		this.SetValue("roundswon", 0);
		this.SetValue("roundslost", 0);
		this.SetValue("matcheswon", 0);
		this.SetValue("matcheslost", 0);
		this.SetValue("matchestied", 0);
		this.SetValue("shots", 0);
		this.SetValue("hits", 0);
		this.SetValue("damage", 0);
		this.SetValue("headshots", 0);
		this.SetValue("points", 0);
	}
	
	public void insertToDb(bool close)
	{
		char formattedQuery[1024];
		char id64[32];
		char ipaddress[32];
		char playername[32];
		int lastconnect;
		char region[32];
		DataPack dp = new DataPack();
		this.GetString("id64", STRING(id64));
		this.GetString("ip", STRING(ipaddress));
		this.GetString("ign", STRING(playername));
		this.GetValue("lastconnect", lastconnect);
		this.GetString("region", STRING(region));
		dp.WriteCell(close);
		dp.WriteCell(this);
		
		g_hThreadedDb.Format(STRING(formattedQuery), Q_INSERT_PLAYER, id64, ipaddress, playername, lastconnect, region, 
			ipaddress, playername, lastconnect, region);
		g_hThreadedDb.Query(insertcb, formattedQuery, dp);
	}
	
	public void updateToDb(bool close)
	{
		char formattedQuery[1024];
		char id64[32];
		char ipaddress[32];
		char playername[32];
		int kills, deaths, assists, mvps, onevstwo, onevsthree, onevsfour, onevsfive, triplekill, quadrakill, pentakill, roundswon, roundslost, matcheswon, matcheslost, matchestied, shots, hits, headshots, 
		points, lastconnect, time, damage;
		DataPack dp = new DataPack();
		this.GetString("id64", STRING(id64));
		this.GetString("ip", STRING(ipaddress));
		this.GetString("ign", STRING(playername));
		this.GetValue("kills", kills);
		this.GetValue("deaths", deaths);
		this.GetValue("assists", assists);
		this.GetValue("mvps", mvps);
		this.GetValue("1v2", onevstwo);
		this.GetValue("1v3", onevsthree);
		this.GetValue("1v4", onevsfour);
		this.GetValue("1v5", onevsfive);
		this.GetValue("triplekill", triplekill);
		this.GetValue("quadrakill", quadrakill);
		this.GetValue("pentakill", pentakill);
		this.GetValue("roundswon", roundswon);
		this.GetValue("roundslost", roundslost);
		this.GetValue("matcheswon", matcheswon);
		this.GetValue("matcheslost", matcheslost);
		this.GetValue("matchestied", matchestied);
		this.GetValue("shots", shots);
		this.GetValue("hits", hits);
		this.GetValue("damage", damage);
		this.GetValue("headshots", headshots);
		this.GetValue("points", points);
		this.GetValue("lastconnect", lastconnect);
		this.GetValue("time", time);
		
		dp.WriteCell(close);
		dp.WriteCell(this);
		
		int uid; this.GetValue("uid", uid);
		int client = GetClientOfUserId(uid);
		if (close)
		{
			if (client != INVALID_ENT_REFERENCE && !(StrContains(id64, "BOT") != -1 || StrContains(id64, "INVALID") != -1))
			{
				time = RoundToFloor(GetEngineTime() - g_fJoinTime[client]);
				PrintToServer("Time on server: %i", time);
			}
		}
		
		g_hThreadedDb.Format(STRING(formattedQuery), Q_UPDATE_PLAYER, ipaddress, playername, kills, 
			deaths, assists, mvps, onevstwo, onevsthree, onevsfour, onevsfive, triplekill, quadrakill, pentakill, shots, hits, damage, headshots, 
			roundswon, roundslost, matcheswon, matcheslost, matchestied, points, lastconnect, time, id64);
		g_hThreadedDb.Query(updatecb, formattedQuery, dp);
	}
	
	public void importFromDb(bool close)
	{
		char formattedQuery[1024];
		char id64[32];
		DataPack dp = new DataPack();
		this.GetString("id64", STRING(id64));
		dp.WriteCell(close);
		dp.WriteCell(this);
		
		g_hThreadedDb.Format(STRING(formattedQuery), Q_GET_PLAYER, id64);
		g_hThreadedDb.Query(importcb, formattedQuery, dp, DBPrio_High);
	}
	
}

bool g_bDbReady;
bool g_bGatherStats = false;

Handle g_hOnKill;
Handle g_hOnDeath;
Handle g_hOnAssist;
Handle g_hOnRoundWon;
Handle g_hOnRoundMVP;
Handle g_hOnPlayerRoundWon;
Handle g_hOnRoundLost;
Handle g_hOnPlayerRoundLost;
Handle g_hOnShotFired;
Handle g_hOnPlayerHit;
Handle g_hOnHeadShot;
PlayerStatsTracker g_hPlayers[MAXPLAYERS];
int g_RoundKills[MAXPLAYERS + 1]; 

int g_RoundClutchingEnemyCount[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "Player Statistics", 
	author = PLUGIN_AUTHOR, 
	description = "Records stats of players during game play.", 
	version = PLUGIN_VERSION, 
	url = "DistrictNine.Host"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("Basic Player Stats");
	
	g_hOnKill = CreateGlobalForward("OnKill", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	g_hOnDeath = CreateGlobalForward("OnDeath", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	g_hOnAssist = CreateGlobalForward("OnAssist", ET_Ignore, Param_Cell, Param_Cell);
	g_hOnRoundWon = CreateGlobalForward("OnRoundWon", ET_Ignore, Param_Cell);
	g_hOnRoundMVP = CreateGlobalForward("OnRoundMVP", ET_Ignore, Param_Cell);
	g_hOnPlayerRoundWon = CreateGlobalForward("OnPlayerRoundWon", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	g_hOnRoundLost = CreateGlobalForward("OnRoundLost", ET_Ignore, Param_Cell);
	g_hOnPlayerRoundLost = CreateGlobalForward("OnPlayerRoundLost", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	g_hOnShotFired = CreateGlobalForward("OnShotFired", ET_Ignore, Param_Cell, Param_Cell, Param_String);
	g_hOnPlayerHit = CreateGlobalForward("OnPlayerHit", ET_Ignore, Param_Cell, Param_Cell);
	g_hOnHeadShot = CreateGlobalForward("OnHeadShot", ET_Ignore, Param_Cell, Param_Cell);
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	Database.Connect(OnDbConnect, "BasicPlayerStats");

	g_serverRegion = CreateConVar("sm_region", "N/A", "Which region the players are playing on. NA = North America, EU= Europe, OCE = Ocenaic");
	AutoExecConfig(true, "stats");
	HookEvent("weapon_fire", Event_PlayerShoot);
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("round_mvp", Event_RoundMVP);
	HookEvent("player_connect_full", Event_PlayerConnect);
}

/* Enable Or Disable Points In Warmup and Knife Round */
public void OnGameFrame()
{
	//In Warmup
	if(GameRules_GetProp("m_bWarmupPeriod") == 1 || Get5_GetGameState() != Get5State_Live) g_bGatherStats = false;
	else g_bGatherStats = true;	
}

public void OnDbConnect(Database db, const char[] error, any data)
{
	if (db == null)
	{
		LogError("Database failure: %s", error);
	}
	else
	{
		g_hThreadedDb = db;
	}
}

public void Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!VALIDPLAYER(client) && !DEBUG)
	{
		return;
	}
	
	if (DEBUG)
	{
		PrintToServer("OnClientPostAdminCheck -> %d", client);
	}
	
	g_hPlayers[client] = new PlayerStatsTracker(client);
	g_hPlayers[client].insertToDb(false);
	g_fJoinTime[client] = GetEngineTime();
}

// public void OnClientPostAdminCheck(int client)
// {
// 	if (!VALIDPLAYER(client) && !DEBUG)
// 	{
// 		return;
// 	}
	
// 	if (DEBUG)
// 	{
// 		PrintToServer("OnClientPostAdminCheck -> %d", client);
// 	}
	
// 	g_hPlayers[client] = new PlayerStatsTracker(client);
// 	g_hPlayers[client].insertToDb(false);
// 	g_fJoinTime[client] = GetEngineTime();
// }

public void OnClientDisconnect(int client)
{
	if (!VALIDPLAYER(client) && !DEBUG)
	{
		return;
	}
	
	if (DEBUG)
	{
		PrintToServer("OnClientDisconnect -> %d", client);
	}
	
	if (g_hPlayers[client] == null)
	{
		return;
	}
	if (!hasCalculated)
	{
		g_hPlayers[client].updateToDb(true);
	}
	if (Get5_GetGameState() != Get5State_Live)
	{
		delete g_hPlayers[client];
	}
}



// This works fine.
public Action Event_PlayerShoot(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	char weaponname[32];
	event.GetString("weapon", STRING(weaponname));
	if (!g_bGatherStats) return Plugin_Handled;
	if (StrContains(weaponname, "knife") != -1 || 
		StrEqual(weaponname, "bayonet") || 
		StrEqual(weaponname, "melee") || 
		StrEqual(weaponname, "axe") || 
		StrEqual(weaponname, "hammer") || 
		StrEqual(weaponname, "spanner") || 
		StrEqual(weaponname, "fists") || 
		StrEqual(weaponname, "hegrenade") || 
		StrEqual(weaponname, "flashbang") || 
		StrEqual(weaponname, "smokegrenade") || 
		StrEqual(weaponname, "inferno") || 
		StrEqual(weaponname, "molotov") || 
		StrEqual(weaponname, "incgrenade") ||
		StrContains(weaponname, "decoy") != -1 ||
		StrEqual(weaponname, "firebomb") ||
		StrEqual(weaponname, "diversion") ||
		StrContains(weaponname, "breachcharge") != -1)
	return Plugin_Handled; 
	
	if (client && (VALIDPLAYER(client) || DEBUG))
	{
		int uid = GetClientUserId(client);
		if (g_hPlayers[client] != null && g_hPlayers[client].isPlayersStats(uid))
		{
			g_hPlayers[client].incrementShots(1);
			
			Call_StartForward(g_hOnShotFired);
			Call_PushCell(client);
			Call_PushCell(1);
			Call_PushString(weaponname);
			Call_Finish();
			
			if (DEBUG)
			{
				PrintToServer("Client %d fired a shot.", client);
			}
			
		}
	}
}

public Action Event_RoundMVP(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);

	if (!g_bGatherStats) return Plugin_Handled;

	if (client && (VALIDPLAYER(client) || DEBUG))
	{
		int uid = GetClientUserId(client);
		if (g_hPlayers[client] != null && g_hPlayers[client].isPlayersStats(uid))
		{
			g_hPlayers[client].incrementMVPs();
			Call_StartForward(g_hOnRoundMVP);
			Call_PushCell(client);
			Call_Finish();
		}
	}
	return Plugin_Continue;
}

static int GetClutchingClient(int csTeam) {
  int client = -1;
  int count = 0;
  for (int i = 1; i <= MaxClients; i++) {
    if (VALIDPLAYER(i) && GetClientTeam(i) == csTeam) {
      client = i;
      count++;
    }
  }

  if (count == 1) {
    return client;
  } else {
    return -1;
  }
}

stock int CountAlivePlayersOnTeam(int csTeam) {
  int count = 0;
  for (int i = 1; i <= MaxClients; i++) {
    if (VALIDPLAYER(i) && GetClientTeam(i) == csTeam) {
      count++;
    }
  }
  return count;
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)  {
	int victimid = event.GetInt("userid");
	int attackerid = event.GetInt("attacker");
	int assisterid = event.GetInt("assister");
	int victim = GetClientOfUserId(victimid);
	int attacker = GetClientOfUserId(attackerid);
	int assister = GetClientOfUserId(assisterid);

	int hitgroup = GetEventInt(event, "hitgroup");
	int idamage = event.GetInt("dmg_health");

	if (!g_bGatherStats) return Plugin_Handled;

	if (attacker && (VALIDPLAYER(attacker) || DEBUG))
	{
		int aid = GetClientUserId(attacker);
		if (g_hPlayers[attacker] != null && g_hPlayers[attacker].isPlayersStats(aid))
		{
			g_hPlayers[attacker].incrementHits();
			g_hPlayers[attacker].incrementDamage(idamage);
			Call_StartForward(g_hOnPlayerHit);
			Call_PushCell(victim);
			Call_PushCell(attacker);
			// Call_PushCell(idamage); // This line is causing issues.
			Call_Finish();
			
			if (DEBUG)
			{
				PrintToServer("Attacker %d hit victim %d.", attacker, victim);
			}
			
			if (GetClientHealth(victim) <= 0 && hitgroup == 1)
			{
				g_hPlayers[attacker].incrementHeadshots();
				Call_StartForward(g_hOnHeadShot);
				Call_PushCell(victim);
				Call_PushCell(attacker);
				Call_Finish();
				
				if (DEBUG)
				{
					PrintToServer("Attacker %d headshot victim %d.", attacker, victim);
				}
				
			}
		}
	}

	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victimid = event.GetInt("userid");
	int attackerid = event.GetInt("attacker");
	int assisterid = event.GetInt("assister");
	int victim = GetClientOfUserId(victimid);
	int attacker = GetClientOfUserId(attackerid);
	int assister = GetClientOfUserId(assisterid);

	if (attacker != 0 && (IsFakeClient(victim)) || IsFakeClient(attacker) || victim == attacker || attacker == 0) return Plugin_Handled;

	int tCount = CountAlivePlayersOnTeam(CS_TEAM_T);
	int ctCount = CountAlivePlayersOnTeam(CS_TEAM_CT);

	if (!g_bGatherStats) return Plugin_Handled;
	
	if (victim && (VALIDPLAYER(victim) || DEBUG) && g_hPlayers[victim] != null && g_hPlayers[victim].isPlayersStats(victimid))
	{
		g_hPlayers[victim].incrementDeaths();
		Call_StartForward(g_hOnDeath);
		Call_PushCell(victim);
		Call_PushCell(attacker);
		Call_PushCell(assister);
		Call_Finish();
		
		if (DEBUG)
		{
			PrintToServer("Victim %d died.", victim);
		}
		
	}
	
	if (attacker && (VALIDPLAYER(attacker) || DEBUG) && g_hPlayers[attacker] != null && g_hPlayers[attacker].isPlayersStats(attackerid))
	{
		g_RoundKills[attacker]++;
		g_hPlayers[attacker].incrementKills();
		Call_StartForward(g_hOnKill);
		Call_PushCell(attacker);
		Call_PushCell(victim);
		Call_PushCell(event.GetBool("headshot"));
		Call_Finish();
		
		if (DEBUG)
		{
			PrintToServer("Attacker %d killed victim %d.", attacker, victim);
		}
		
	}
	
	if (assister && (VALIDPLAYER(assister) || DEBUG) && g_hPlayers[assister] != null && g_hPlayers[assister].isPlayersStats(assisterid))
	{
		g_hPlayers[assister].incrementAssists();
		Call_StartForward(g_hOnAssist);
		Call_PushCell(assister);
		Call_PushCell(victim);
		Call_Finish();
		
		if (DEBUG)
		{
			PrintToServer("Assister %d assisted in the death of victim %d.", assister, victim);
		}
		
	}

	if (g_iClutchFor > 0)
	{
		return Plugin_Handled;
	}

	if (tCount == 1 && ctCount <= 5) {
		g_iClutchFor = CS_TEAM_T;
		int clutcher = GetClutchingClient(CS_TEAM_T);
		g_iOpponents = ctCount;
		g_RoundClutchingEnemyCount[clutcher] = g_iOpponents;
	}
	else if (ctCount == 1 && tCount <= 5) {
		g_iClutchFor = CS_TEAM_CT;
		int clutcher = GetClutchingClient(CS_TEAM_CT);
		g_iOpponents = tCount;
		g_RoundClutchingEnemyCount[clutcher] = g_iOpponents;
	}
	
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bGatherStats) return Plugin_Handled;

	int team = event.GetInt("winner");
	int otherTeam = (team == 2) ? 3 : 2;
	Call_StartForward(g_hOnRoundWon);
	Call_PushCell(team);
	Call_Finish();
	Call_StartForward(g_hOnRoundLost);
	Call_PushCell(otherTeam);
	Call_Finish();
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!VALIDPLAYER(i) && !DEBUG)
		{
			continue;
		}
		
		if (g_hPlayers[i] == null)
		{
			continue;
		}

		
		int clientteam;
		if ((clientteam = GetClientTeam(i)) == team)
		{
			switch (g_RoundKills[i]) {
				case 3:
					g_hPlayers[i].setTripleKill();
				case 4:
					g_hPlayers[i].setQuadraKill();
				case 5:
					g_hPlayers[i].setPentaKill();
			}
			switch (g_RoundClutchingEnemyCount[i]) {
				case 2:
					g_hPlayers[i].setOneVTwo();
				case 3:
					g_hPlayers[i].setOneVThree();
				case 4:
					g_hPlayers[i].setOneVFour();
				case 5:
					g_hPlayers[i].setOneVFive();
			}
			g_RoundKills[i] = 0;
			g_hPlayers[i].incrementRoundsWon();


			Call_StartForward(g_hOnPlayerRoundWon);
			Call_PushCell(i);
			Call_PushCell(team);
			Call_PushCell(g_RoundClutchingEnemyCount[i]);
			Call_Finish();
			g_RoundClutchingEnemyCount[i] = 0;
			
			if (DEBUG)
			{
				PrintToServer("Client %d on Team %d won.", i, team);
			}
			
		}
		else if (clientteam == otherTeam)
		{
			switch (g_RoundKills[i]) {
				case 3:
					g_hPlayers[i].setTripleKill();
				case 4:
					g_hPlayers[i].setQuadraKill();
				case 5:
					g_hPlayers[i].setPentaKill();
			}
			g_RoundKills[i] = 0;
			g_hPlayers[i].incrementRoundsLost();

			Call_StartForward(g_hOnPlayerRoundLost);
			Call_PushCell(i);
			Call_PushCell(otherTeam);
			Call_Finish();
			
			if (DEBUG)
			{
				PrintToServer("Client %d on Team %d lost.", i, otherTeam);
			}
			
		}
		else
		{
			if (DEBUG)
			{
				PrintToServer("Client %d can't win or lose coz they aren't on a team!", i);
			}
			
		}
		g_hPlayers[i].updateToDb(false);
		g_hPlayers[i].resetStats();
		g_iClutchFor = 0;
		g_iOpponents = 0;
	}
	return Plugin_Continue;
}

/*
public void FireBulletsPost(int client, int shots, const char[] weaponname)
{
	PrintToServer("Do You Even Flex?");
	if (client && (VALIDPLAYER(client) || DEBUG))
	{
		int uid = GetClientUserId(client);
		if (g_hPlayers[client] != null && g_hPlayers[client].isPlayersStats(uid))
		{
			g_hPlayers[client].incrementShots(shots);
			Call_StartForward(g_hOnShotFired);
			Call_PushCell(client);
			Call_PushCell(shots);
			Call_PushString(weaponname);
			Call_Finish();
			
			if (DEBUG)
			{
				PrintToServer("Client %d fired a shot.", client);
			}
			
		}
	}
}
*/
	// public void TraceAttackPost(int victim, int attacker, int inflictor, float damage, int damagetype, int ammotype, int hitbox, int hitgroup)
	// {
	// 	if (attacker && (VALIDPLAYER(attacker) || DEBUG))
	// 	{
	// 		hitgroup = g_iNextHitgroup[victim];
	// 		int aid = GetClientUserId(attacker);
	// 		if (g_hPlayers[attacker] != null && g_hPlayers[attacker].isPlayersStats(aid))
	// 		{
	// 			g_hPlayers[attacker].incrementHits();
	// 			Call_StartForward(g_hOnPlayerHit);
	// 			Call_PushCell(victim);
	// 			Call_PushCell(attacker);
	// 			Call_PushFloat(damage);
	// 			Call_Finish();
				
	// 			if (DEBUG)
	// 			{
	// 				PrintToServer("Attacker %d hit victim %d.", attacker, victim);
	// 			}
				
	// 			if (GetClientHealth(victim) <= 0 && hitgroup == 1)
	// 			{
	// 				g_hPlayers[attacker].incrementHeadshots();
	// 				Call_StartForward(g_hOnHeadShot);
	// 				Call_PushCell(victim);
	// 				Call_PushCell(attacker);
	// 				Call_Finish();
					
	// 				if (DEBUG)
	// 				{
	// 					PrintToServer("Attacker %d headshot victim %d.", attacker, victim);
	// 				}
					
	// 			}
	// 		}
	// 	}
	// }

public void Get5_OnSeriesResult(MatchTeam seriesWinner, int team1MapScore, int team2MapScore)
{
	MatchTeam oppositeSeriesTeam;

	if (seriesWinner == MatchTeam_Team1)
	{
		oppositeSeriesTeam = MatchTeam_Team2;
	}
	else if (seriesWinner == MatchTeam_Team2)
	{
		oppositeSeriesTeam = MatchTeam_Team1;
	}
	else
	{
		oppositeSeriesTeam = MatchTeam_TeamNone;
	}


	if (!hasCalculated)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!VALIDPLAYER(i) && !DEBUG)
			{
				continue;
			}
			
			if (g_hPlayers[i] == null)
			{
				continue;
			}
			
			char auth[32];
			if (!g_hPlayers[i].GetString("id64", STRING(auth)))
			{
				continue;
			}
			
			MatchTeam team = Get5_GetPlayerTeam(auth);
			if (team == seriesWinner)
			{
				g_hPlayers[i].incrementMatchesWon();

			}
			else if (team == oppositeSeriesTeam)
			{
				g_hPlayers[i].incrementMatchesLost();
			}
			else
			{
				g_hPlayers[i].incrementMatchesTied();
			}
			
			g_hPlayers[i].addPoints(CS_GetClientContributionScore(i));
			g_hPlayers[i].updateToDb(true);
			hasCalculated = true;
		}
	}
}

// This is useless.
// public Action Timer_ClosePlayerStats(Handle timer, any data)
// {
// 	//delete view_as<Handle>(data);
// }

public void createtablecb(Database db, DBResultSet results, const char[] error, any data)
{
	if (!ISEMPTY(error))
	{
		LogError(error);
		return;
	}
	
	g_bDbReady = true;
}


// WTF IS THIS METHOD? - Can someone define this for me?
public void insertcb(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack dp = view_as<DataPack>(data);
	dp.Reset();
	
	bool close = view_as<bool>(dp.ReadCell());
	PlayerStatsTracker ps = view_as<PlayerStatsTracker>(dp.ReadCell());
	
	if (!ISEMPTY(error))
	{
		LogError(error);
	}
	
	if (close)
	{
		// CreateTimer(1.0, Timer_ClosePlayerStats, ps);
	}
}

public void updatecb(Database db, DBResultSet results, const char[] error, any data)
{	
	DataPack dp = view_as<DataPack>(data);
	dp.Reset();
	
	bool close = view_as<bool>(dp.ReadCell());
	PlayerStatsTracker ps = view_as<PlayerStatsTracker>(dp.ReadCell());
	
	if (!ISEMPTY(error))
	{
		LogError(error);
	}
	
	if (close)
	{
		// CreateTimer(1.0, Timer_ClosePlayerStats, ps);
	}
}

public void importcb(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack dp = view_as<DataPack>(data);
	dp.Reset();
	
	// bool close = view_as<bool>(dp.ReadCell());
	PlayerStatsTracker ps = view_as<PlayerStatsTracker>(dp.ReadCell());
	
	if (!ISEMPTY(error))
	{
		LogError(error);
		// if (close)
		// {
		// 	CreateTimer(1.0, Timer_ClosePlayerStats, ps);
		// 	return;
		// }
	}
		 
	if (results == null)
	{
		LogError("Failed to get results. results == null");
	}
	else
	{
		if (results.RowCount == 0)
		{
			LogError("No row returned for import query.");
		}
		else
		{
			results.FetchRow();
			ps.SetValue("kills", results.FetchInt(3));
			ps.SetValue("deaths", results.FetchInt(4));
			ps.SetValue("assists", results.FetchInt(5));
			ps.SetValue("shots", results.FetchInt(6));
			ps.SetValue("hits", results.FetchInt(7));
			ps.SetValue("headshots", results.FetchInt(8));
			ps.SetValue("points", results.FetchInt(9));
			PrintToServer("Imported results from db.");
		}
	}
	// if (close)
	// {
	// 	CreateTimer(1.0, Timer_ClosePlayerStats, ps);
	// }
}

bool VALIDPLAYER(int client)
{
	if ( !( 1 <= client <= MaxClients ) || !IsClientInGame(client) ) return false; 
    else return true; 
}

// bool VALIDPLAYER(int client)
// {
// 	if (0 < client <= MaxClients)
// 	{
// 		if (IsClientInGame(client) && !IsClientReplay(client) && !IsClientSourceTV(client) && !IsFakeClient(client))
// 		{
// 			return true;
// 		}
// 	}
	
// 	return false;
// } 