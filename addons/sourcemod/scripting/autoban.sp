#include <get5>
#include <sdkhooks>
#include <sdktools>
#include <SteamWorks>
#include <socket>
#include <smjansson>
#include <base64>
#include <loadmatch>

float g_fTeamDamage[MAXPLAYERS + 1];

int g_iAfkTime[MAXPLAYERS + 1];
int g_iTeamKills[MAXPLAYERS + 1];
int g_iRetryTimes[MAXPLAYERS + 1];
int g_iMatchStartTime;
int g_iLastButtons[MAXPLAYERS + 1];
int g_iButtonsArraySize = 5;
int iObserverMode[MAXPLAYERS+1] = -1;

bool g_bLate;
bool g_bBanned[MAXPLAYERS + 1];
bool g_bPlayerAfk[MAXPLAYERS + 1] = true;

float g_fLastPos[MAXPLAYERS + 1][3];

Database g_Database = null;

enum BanReason 
{
	REASON_OTHER = -1,
	REASON_AFK,
	REASON_LEAVE,
	REASON_DAMAGE
};

BanReason g_eBanReason[MAXPLAYERS + 1];

ConVar g_hCVFallbackTime;
ConVar g_hCVServerIp;
//ConVar g_hCVPackageKey;
ConVar g_hCVGracePeriod;

Handle g_hSocket;

public Plugin myinfo = 
{
	name = "Auto Match Ban",
	author = "DN.H | The Doggy",
	description = "Ban Noobs",
	version = "1.0.0",
	url = "DistrictNine.Host"
};

public void ResetVars(int Client)
{
	g_fTeamDamage[Client] = 0.0;
	g_iAfkTime[Client] = 0;
	g_iTeamKills[Client] = 0;
	g_iRetryTimes[Client] = 0;
	g_bBanned[Client] = false;
	g_eBanReason[Client] = REASON_OTHER;
	g_iLastButtons[Client] = 0;
}

public void OnMapStart()
{
	g_iMatchStartTime = 0;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if(late)
		g_bLate = true;

	return APLRes_Success;
}

public void OnPluginStart()
{
	//Hook Event
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);

	//Create ConVar
	g_hCVFallbackTime = CreateConVar("sm_autoban_fallback_time", "120", "Time a player should be banned for if MySQL ban fails.");
	g_hCVServerIp = CreateConVar("sqlmatch_websocket_ip", "127.0.0.1", "IP to connect to for sending ban messages.");
	//g_hCVPackageKey = CreateConVar("sm_autoban_package_key", "PLEASECHANGEME", "The package key / Secret key to communicate with the socket.");
	g_hCVGracePeriod = CreateConVar("sm_autoban_grace_period", "150", "The amount of time a player has to rejoin before being banned for afk/disconnect bans.");

	//Create Socket
	g_hSocket = SocketCreate(SOCKET_TCP, OnSocketError);

	//Set Socket Options
	SocketSetOption(g_hSocket, SocketReuseAddr, 1);
	SocketSetOption(g_hSocket, SocketKeepAlive, 1);

	//Connect Socket
	if(!SocketIsConnected(g_hSocket))
		ConnectRelay();

	CreateTimer(1.0, GlobalSecondTimer, _, TIMER_REPEAT);
	Database.Connect(SQL_InitialConnection, "auto_ban");
}

public Action GlobalSecondTimer(Handle hTimer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && IsPlayerAlive(i) && !(IsPaused() || InFreezeTime()))
		{
			g_iAfkTime[i] = g_bPlayerAfk[i] ? ++g_iAfkTime[i] : 0;
		}
	}
	return Plugin_Continue;
}

void ConnectRelay()
{	
	if (!SocketIsConnected(g_hSocket))
	{
		char sHost[32];
		g_hCVServerIp.GetString(sHost, sizeof(sHost));
		SocketConnect(g_hSocket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, sHost, 8889);
	}
	else
		PrintToServer("Socket is already connected?");
}

public Action Timer_Reconnect(Handle timer)
{
	ConnectRelay();
}

void StartReconnectTimer()
{
	if (SocketIsConnected(g_hSocket))
		SocketDisconnect(g_hSocket);
		
	CreateTimer(10.0, Timer_Reconnect);
}

public int OnSocketDisconnected(Handle socket, any arg)
{	
	StartReconnectTimer();
	
	PrintToServer("Socket disconnected");
}

public int OnSocketError(Handle socket, int errorType, int errorNum, any ary)
{
	StartReconnectTimer();
	
	LogError("Socket error %i (errno %i)", errorType, errorNum);
}

public int OnSocketConnected(Handle socket, any arg)
{	
	PrintToServer("Successfully Connected");
}

public int OnSocketReceive(Handle socket, const char[] receiveData, int dataSize, any arg)
{
	PrintToServer(receiveData);
}

public Action AttemptMySQLConnection(Handle timer)
{
	if (g_Database != null)
	{
		delete g_Database;
		g_Database = null;
	}
	
	char sFolder[32];
	GetGameFolderName(sFolder, sizeof(sFolder));
	if (SQL_CheckConfig("auto_ban"))
	{
		PrintToServer("Initalizing Connection to MySQL Database");
		Database.Connect(SQL_InitialConnection, "auto_ban");
	}
	else
		LogError("Database Error: No Database Config Found! (%s/addons/sourcemod/configs/databases.cfg)", sFolder);

	return Plugin_Stop;
}

public void SQL_InitialConnection(Database db, const char[] sError, int data)
{
	if (db == null)
	{
		LogError("Database Error: %s", sError);
		CreateTimer(10.0, AttemptMySQLConnection);
		return;
	}
	
	char sDriver[16];
	db.Driver.GetIdentifier(sDriver, sizeof(sDriver));
	if (StrEqual(sDriver, "mysql", false)) LogMessage("MySQL Database: connected");
	
	g_Database = db;
	CreateAndVerifySQLTables();
}

public void CreateAndVerifySQLTables()
{
	if(g_bLate)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
				CreateTimer(0.1, Timer_CheckBan, GetClientUserId(i));
			}
		}
	}
}

public Action Timer_CheckBan(Handle hTimer, int userID)
{
	int Client = GetClientOfUserId(userID);
	if(!IsValidClient(Client)) return Plugin_Stop;

	CheckBanStatus(Client);
	return Plugin_Stop;
}

public void CheckBanStatus(int Client)
{
	if(g_Database == null) return;

	if(!IsValidClient(Client)) return;

	char sSteamID[64];
	if(!GetClientAuthId(Client, AuthId_SteamID64, sSteamID, sizeof(sSteamID)) && g_iRetryTimes[Client] < 5)
	{
		g_iRetryTimes[Client]++;
		LogMessage("Failed to get SteamID for player %N, retrying in 30 seconds.", Client);
		CreateTimer(30.0, Timer_CheckBan, GetClientUserId(Client));
	}
	else if(g_iRetryTimes[Client] >= 5)
	{
		LogError("Failed to get SteamID for player %N 5 times, kicking player instead.", Client);
		g_bBanned[Client] = true;
		KickClient(Client, "Failed to get your SteamID");
	}

	char sQuery[1024];
	Format(sQuery, sizeof(sQuery), "SELECT active, reason FROM bans WHERE steamid='%s';", sSteamID);
	g_Database.Query(SQL_SelectBan, sQuery, GetClientUserId(Client));
}

public void SQL_SelectBan(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
		return;
	}

	if(!results.FetchRow()) return;

	int Client = GetClientOfUserId(data);
	if(!IsValidClient(Client)) return;

	do
	{
		int activeCol, reasonCol, active;
		results.FieldNameToNum("active", activeCol);
		active = results.FetchInt(activeCol);

		if(active != 1) continue;

		char sReason[128];
		results.FieldNameToNum("reason", reasonCol);
		results.FetchString(reasonCol, sReason, sizeof(sReason));
		g_bBanned[Client] = true;
		KickClient(Client, sReason);
	} while(results.FetchRow());
}

public void BanPlayer(int Client)
{
	if(!IsValidClient(Client)) return;

	if(g_bBanned[Client]) return;

	char sSteamID[64], sQuery[1024], sReason[128], sSmallReason[16];
	if(!GetClientAuthId(Client, AuthId_SteamID64, sSteamID, sizeof(sSteamID)))
	{
		LogError("BanPlayer(): Unable to get player %N's SteamID, trying to ban player via SM natives instead.", Client);
		if(!BanClient(Client, g_hCVFallbackTime.IntValue, BANFLAG_AUTO, "Fallback ban", "Fallback ban"))
			LogError("BanPlayer(): Failed to ban player %N via SM natives :(", Client);
		return;
	}

	switch(g_eBanReason[Client])
	{
		case REASON_AFK: Format(sSmallReason, sizeof(sSmallReason), "AFK");
		case REASON_LEAVE: Format(sSmallReason, sizeof(sSmallReason), "Left Match");
		case REASON_DAMAGE: Format(sSmallReason, sizeof(sSmallReason), "Team Damage");
		default: Format(sSmallReason, sizeof(sSmallReason), "Something");
	}

	g_bBanned[Client] = true;
	Format(sReason, sizeof(sReason), "Automatic %s Ban", sSmallReason);
	KickClient(Client, sReason);

	DataPack steamPack = new DataPack();
	steamPack.WriteString(sSteamID);
	steamPack.WriteString(sReason);

	Format(sQuery, sizeof(sQuery), "INSERT INTO bans (steamid, reason, active) VALUES ('%s', '%s', 1);", sSteamID, sReason);
	g_Database.Query(SQL_InsertBan, sQuery, steamPack);
}

public void ExecuteBanMessageSocket(char[] sSteamID, char[] sReason)
{

	char sData[2048], sDataEncoded[4096], sMatchId[256];
	GetCurrentMatchId(sMatchId);

	Handle jsonObj = json_object();
	json_object_set_new(jsonObj, "type", json_integer(2));
	json_object_set_new(jsonObj, "match_id", json_string(sMatchId));
	json_object_set_new(jsonObj, "steamid", json_string(sSteamID));
	json_object_set_new(jsonObj, "reason", json_string(sReason));
	json_dump(jsonObj, sData, sizeof(sData), 0, false, false, true);
	CloseHandle(jsonObj);

	if(!SocketIsConnected(g_hSocket))
		ConnectRelay();

	LogMessage("ExecuteBanMessageSocket(): Data before base64 encode: %s", sData);

	EncodeBase64(sDataEncoded, sizeof(sDataEncoded), sData);

	LogMessage("ExecuteBanMessageSocket(): Data after base64 encode: %s", sDataEncoded);

	SocketSend(g_hSocket, sDataEncoded, sizeof(sDataEncoded));

	char sSocketIp[64];
	g_hCVServerIp.GetString(sSocketIp, sizeof(sSocketIp));
	LogMessage("ExecuteBanMessageSocket(): Data: %s sent to %s:8889", sDataEncoded, sSocketIp);

}

public void SQL_InsertBan(Database db, DBResultSet results, const char[] sError, DataPack data)
{
	char sSteamID[64];
	char sReason[128];
	 
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);

		// char sSteamID[64], char sReason[128];
		data.Reset();
		data.ReadString(sSteamID, sizeof(sSteamID));
		data.ReadString(sReason, sizeof(sReason));
		delete data;
		LogError("SQL_InsertBan(): Failed to insert ban for SteamID %s, trying to ban via SM natives instead.", sSteamID);
		if(!BanIdentity(sSteamID, g_hCVFallbackTime.IntValue, BANFLAG_AUTHID, "Fallback ban"))
			LogError("SQL_InsertBan(): Failed to ban SteamID %s via SM natives :(", sSteamID);
		return;
	}

	data.Reset();
	data.ReadString(sSteamID, sizeof(sSteamID));
	data.ReadString(sReason, sizeof(sReason));
	delete data;
	ExecuteBanMessageSocket(sSteamID, sReason);
}

public void Get5_OnGoingLive(int mapNumber)
{
	g_iMatchStartTime = GetTime();
}

public void OnClientPostAdminCheck(int Client)
{
	SDKHook(Client, SDKHook_OnTakeDamage, OnTakeDamage);
	CheckBanStatus(Client);
}

public void OnClientPutInServer(int Client)
{
	ResetVars(Client);

}

/* Using player_disconnect event instead */
//	public void OnClientDisconnect_Post(int Client)
//	{
//		if(Get5_GetGameState() <= Get5State_GoingLive || g_bBanned[Client]) return;

//		if(GetTime() - g_iMatchStartTime >= 240)
//		{
//			char sSteamID[64];
//			if(!GetClientAuthId(Client, AuthId_SteamID64, sSteamID, sizeof(sSteamID)))
//			{
//				LogError("OnClientDisconnect_Post(): Failed to get %N's SteamID, not going to add player to disconnect list.", Client);
//				return;
//			}

//			DataPack disconnectPack = new DataPack();
//			disconnectPack.WriteString(sSteamID);
//			disconnectPack.WriteString("Automatic Left Match Ban");
//			CreateTimer(g_hCVGracePeriod.FloatValue, Timer_DisconnectBan, disconnectPack);
//		}
//	}

void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
	// If the game hasn't gone live yet, the client isn't valid or the client is already marked as banned return
	int Client = GetClientOfUserId(event.GetInt("userid"));
	if(Get5_GetGameState() <= Get5State_GoingLive || !IsValidClient(Client) || g_bBanned[Client])
	{
		LogError("Event_PlayerDisconnect(): Match isn't live, client isn't valid or client is already banned.");
		return;
	}

	// If the client was disconnected by anything other than themselves return
	char sDisconnectReason[32];
	event.GetString("reason", sDisconnectReason, sizeof(sDisconnectReason));
	if(!StrEqual(sDisconnectReason, "disconnect", false))
	{
		LogError("Event_PlayerDisconnect(): Unexpected value for disconnect reason: %s. Expected value: disconnect", sDisconnectReason);
		return;
	}

	// If the client's steamid isn't valid return
	char sSteamID[64];
	event.GetString("networkid", sSteamID, sizeof(sSteamID));
	if(sSteamID[7] != ':')
	{
		LogError("Event_PlayerDisconnect(): Unexpected value for steamid %c. Expected value: :", sSteamID[7]);
		return;
	}
	if(!GetClientAuthId(Client, AuthId_SteamID64, sSteamID, sizeof(sSteamID)))
	{
		LogError("Event_PlayerDisconnect(): Failed to get %N's steamid64.");
		return;
	}

	// If it has been 240 seconds or more since the match started, create a disconnect timer for the client
	if(GetTime() - g_iMatchStartTime >= 240)
	{
		g_bBanned[Client] = true;
		DataPack disconnectPack = new DataPack();
		disconnectPack.WriteString(sSteamID);
		disconnectPack.WriteString("Automatic Left Match Ban");
		CreateTimer(g_hCVGracePeriod.FloatValue, Timer_DisconnectBan, disconnectPack);
	}
	else
		LogError("Event_PlayerDisconnect(): It hasn't been 240 seconds since the match started.");
}

public Action Timer_DisconnectBan(Handle hTimer, DataPack disconnectPack)
{
	char sSteamID[64], sCompareId[64];
	disconnectPack.Reset();
	disconnectPack.ReadString(sSteamID, sizeof(sSteamID));

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || g_bBanned[i]) continue;

		if(!GetClientAuthId(i, AuthId_SteamID64, sCompareId, sizeof(sCompareId))) continue;

		if(StrEqual(sSteamID, sCompareId)) return Plugin_Stop;
	}

	char sQuery[1024];
	Format(sQuery, sizeof(sQuery), "INSERT INTO bans (steamid, reason, active) VALUES ('%s', 'Automatic Left Match Ban', 1);", sSteamID);
	g_Database.Query(SQL_InsertBan, sQuery, disconnectPack);
	
	return Plugin_Stop;
}

public Action Timer_AfkBan(Handle hTimer, DataPack disconnectPack)
{
	char sSteamID[64], sCompareId[64];
	disconnectPack.Reset();
	disconnectPack.ReadString(sSteamID, sizeof(sSteamID));

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || g_bBanned[i]) continue;

		if(!GetClientAuthId(i, AuthId_SteamID64, sCompareId, sizeof(sCompareId))) continue;

		if(StrEqual(sSteamID, sCompareId)) return Plugin_Stop;
	}

	char sQuery[1024];
	Format(sQuery, sizeof(sQuery), "INSERT INTO bans (steamid, reason, active) VALUES ('%s', 'Automatic AFK Ban', 1);", sSteamID);
	g_Database.Query(SQL_InsertBan, sQuery, disconnectPack);

	
	return Plugin_Stop;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if(Get5_GetGameState() <= Get5State_GoingLive) return;

	int iVictim = GetClientOfUserId(event.GetInt("userid"));
	int iAttacker = GetClientOfUserId(event.GetInt("attacker"));

	if(!IsValidClient(iVictim) || !IsValidClient(iAttacker) || g_bBanned[iAttacker]) return;

	if(GetClientTeam(iVictim) == GetClientTeam(iAttacker))
	{
		g_iTeamKills[iAttacker]++;

		if(g_iTeamKills[iAttacker] >= 3)
		{
			g_eBanReason[iAttacker] = REASON_DAMAGE;
			BanPlayer(iAttacker);
			return;
		}
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (Get5_GetGameState() <= Get5State_GoingLive) return;

	int client = GetClientOfUserId(event.GetInt("userid"));

	if (IsValidClient(client))
	{
		g_bPlayerAfk[client] = true;
	}
}

stock bool IsPaused() {
    return GameRules_GetProp("m_bMatchWaitingForResume") != 0;
}  

stock bool InFreezeTime()
{
	return GameRules_GetProp("m_bFreezePeriod") != 0;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	if(Get5_GetGameState() <= Get5State_GoingLive || !IsValidClient(client) || g_bBanned[client] || IsPaused() || InFreezeTime()) return Plugin_Continue;

	if (IsClientSourceTV(client) || IsFakeClient(client))
		return Plugin_Continue;
	
	if (cmdnum <= 0)
		return Plugin_Handled;
	
	g_bPlayerAfk[client] = true;

	if (g_iAfkTime[client] >= 60)
	{
		g_iAfkTime[client] = 0;

		char sSteamID[64];
		if(!GetClientAuthId(client, AuthId_SteamID64, sSteamID, sizeof(sSteamID)))
		{
			LogError("OnPlayerRunCmd(): Failed to get %N's SteamID, not going to add player to disconnect list.", client);
			return Plugin_Continue;
		}

		DataPack disconnectPack = new DataPack();
		disconnectPack.WriteString(sSteamID);
		disconnectPack.WriteString("Automatic AFK Ban");
		g_bBanned[client] = true;
		KickClient(client, "You have %i seconds to rejoin before you are banned for being AFK", g_hCVGracePeriod.IntValue);
		CreateTimer(g_hCVGracePeriod.FloatValue, Timer_AfkBan, disconnectPack);
		return Plugin_Continue;
	}
	
	if ((mouse[0] != 0) || (mouse[1] != 0))
	{
		g_bPlayerAfk[client] = false;
		g_iLastButtons[client] = buttons;
		return Plugin_Continue;
	}
	else
	{
		if(buttons && !(buttons & IN_LEFT || buttons & IN_RIGHT))
		{
			g_bPlayerAfk[client] = false;
			return Plugin_Continue;
		}
	}
	
	return Plugin_Continue;
}

public Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if(!IsValidClient(victim) || !IsValidClient(attacker) || Get5_GetGameState() <= Get5State_GoingLive || g_bBanned[attacker] || IsPaused()) return Plugin_Continue;

	if(GetClientTeam(victim) == GetClientTeam(attacker))
	{
		g_fTeamDamage[attacker] += damage;

		if(g_fTeamDamage[attacker] >= 800)
		{
			g_eBanReason[attacker] = REASON_DAMAGE;
			BanPlayer(attacker);
		}
	}

	return Plugin_Continue;
}

//generic query handler
public void SQL_GenericQuery(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
		return;
	}
}

stock bool IsValidClient(int client)
{
	if (client >= 1 && 
	client <= MaxClients &&
	IsClientConnected(client) &&  
	IsClientInGame(client) &&
	!IsFakeClient(client))
		return true;
	return false;
}