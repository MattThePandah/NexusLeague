#pragma semicolon 1

#define PLUGIN_AUTHOR "Totenfluch"
#define PLUGIN_VERSION "2.0"

#include <sourcemod>
#include <sdktools>
#include <multicolors>
#include <autoexecconfig>

#pragma newdecls required

char dbconfig[] = "thenexus_vipmenu";
Database g_DB;

/*
	https://wiki.alliedmods.net/Checking_Admin_Flags_(SourceMod_Scripting)
	19 -> Custom5
	20 -> Custom6
*/

Handle g_hFlag;
int g_iFlags[20];
int g_iFlagCount = 0;

bool g_bIsVip[MAXPLAYERS + 1];

Handle g_hForward_OnClientLoadedPre;
Handle g_hForward_OnClientLoadedPost;

public Plugin myinfo = 
{
	name = "tVIP (Rowdy Edit)", 
	author = PLUGIN_AUTHOR, 
	description = "VIP functionality with levels", 
	version = PLUGIN_VERSION, 
	url = "https://totenfluch.de"
};

public void OnPluginStart() {
	char error[255];
	g_DB = SQL_Connect(dbconfig, true, error, sizeof(error));
	SQL_SetCharset(g_DB, "utf8");
	
	char createTableQuery[4096];
	Format(createTableQuery, sizeof(createTableQuery), 
		"CREATE TABLE IF NOT EXISTS `tVip` ( \
 		`Id` bigint(20) NOT NULL AUTO_INCREMENT, \
  		`timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP, \
  		`playername` varchar(36) COLLATE utf8_bin NOT NULL, \
  		`playerid` varchar(20) COLLATE utf8_bin NOT NULL, \
  		`enddate` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00', \
  		`admin_playername` varchar(36) COLLATE utf8_bin NOT NULL, \
  		`admin_playerid` varchar(20) COLLATE utf8_bin NOT NULL, \
  		`vip_level` INT NOT NULL, \
 		 PRIMARY KEY (`Id`), \
  		 UNIQUE KEY `playerid_server_id` (`playerid`, `server_id`)  \
  		 ) ENGINE = InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8 COLLATE=utf8_bin;"
		);
	SQL_TQuery(g_DB, SQLErrorCheckCallback, createTableQuery);
	
	g_hFlag = CreateConVar("tnn_vip_flags", "20 19", "0=A, 15=O, 18=R etc. Numeric Flag See: 'https://wiki.alliedmods.net/Checking_Admin_Flags_(SourceMod_Scripting)' for Definitions ---- Level 1: Number1, Level 2: Number2, Level3: Number3");
	
	AutoExecConfig_CleanFile();
	AutoExecConfig_ExecuteFile();
	
	RegConsoleCmd("sm_vips", cmdListVips, "Shows all VIPs");
	RegConsoleCmd("sm_vip", openVipPanel, "Opens the Vip Menu");
	
	g_hForward_OnClientLoadedPre = CreateGlobalForward( "tVip_OnClientLoadedPre", ET_Event, Param_Cell);
	g_hForward_OnClientLoadedPost = CreateGlobalForward( "tVip_OnClientLoadedPost", ET_Event, Param_Cell);
	
	reloadVIPs();
}

public void OnConfigsExecuted() {
	g_iFlagCount = 0;
	char cFlags[256];
	GetConVarString(g_hFlag, cFlags, sizeof(cFlags));
	char cSplinters[20][6];
	for (int i = 0; i < 20; i++)
	strcopy(cSplinters[i], 6, "");
	ExplodeString(cFlags, " ", cSplinters, 20, 6);
	for (int i = 0; i < 20; i++) {
		if (StrEqual(cSplinters[i], ""))
			break;
		g_iFlags[g_iFlagCount++] = StringToInt(cSplinters[i]);
	}
}

public Action openVipPanel(int client, int args) {
	if (g_bIsVip[client]) {
		char playerid[20];
		GetClientAuthId(client, AuthId_Steam2, playerid, sizeof(playerid));
		if (StrContains(playerid, "STEAM_") != -1)
			strcopy(playerid, sizeof(playerid), playerid[8]);
		
		char getDatesQuery[1024];
		Format(getDatesQuery, sizeof(getDatesQuery), "SELECT timestamp,enddate,DATEDIFF(enddate, NOW()) as timeleft,vip_level FROM tVip WHERE playerid = '%s';", playerid);
		
		SQL_TQuery(g_DB, getDatesQueryCallback, getDatesQuery, client);
	}
	return Plugin_Handled;
	
}

public void getDatesQueryCallback(Handle owner, Handle hndl, const char[] error, any data) {
	int client = data;
	char ends[128];
	char started[128];
	char left[64];
	int level;
	while (SQL_FetchRow(hndl)) {
		SQL_FetchString(hndl, 0, started, sizeof(started));
		SQL_FetchString(hndl, 1, ends, sizeof(ends));
		SQL_FetchString(hndl, 2, left, sizeof(left));
		level = SQL_FetchInt(hndl, 3);
	}
	
	Menu VipPanelMenu = CreateMenu(VipPanelMenuHandler);
	char m_started[256];
	char m_ends[256];
	char m_level[256];
	Format(m_started, sizeof(m_started), "Started: %s", started);
	Format(m_ends, sizeof(m_ends), "Expires: %s (%s Days)", ends, left);
	if (level == 1) {
		Format(m_level, sizeof(m_level), "Rank: VIP");
	} else if (level == 2) {
		Format(m_level, sizeof(m_level), "Rank: VIP+");
	}
	SetMenuTitle(VipPanelMenu, "NexusNation VIP Information");
	AddMenuItem(VipPanelMenu, "x", m_started, ITEMDRAW_DISABLED);
	AddMenuItem(VipPanelMenu, "x", m_ends, ITEMDRAW_DISABLED);
	AddMenuItem(VipPanelMenu, "x", m_level, ITEMDRAW_DISABLED);
	DisplayMenu(VipPanelMenu, client, 60);
}

public int VipPanelMenuHandler(Handle menu, MenuAction action, int client, int item) {
	char cValue[32];
	GetMenuItem(menu, item, cValue, sizeof(cValue));
	if (action == MenuAction_Select) {
		// TODO ?
	}
}

public Action cmdListVips(int client, int args) {
	char showOffVIPQuery[1024];
	Format(showOffVIPQuery, sizeof(showOffVIPQuery), "SELECT playername,playerid FROM tVip WHERE NOW() < enddate;");
	SQL_TQuery(g_DB, SQLShowOffVipQuery, showOffVIPQuery, client);
}

public void SQLShowOffVipQuery(Handle owner, Handle hndl, const char[] error, any data) {
	int client = data;
	Menu showOffMenu = CreateMenu(noMenuHandler);
	SetMenuTitle(showOffMenu, "NexusNation VIPs (Thank You!)");
	while (SQL_FetchRow(hndl)) {
		char playerid[20];
		char playername[MAX_NAME_LENGTH + 8];
		SQL_FetchString(hndl, 0, playername, sizeof(playername));
		SQL_FetchString(hndl, 1, playerid, sizeof(playerid));
		AddMenuItem(showOffMenu, playerid, playername, ITEMDRAW_DISABLED);
	}
	DisplayMenu(showOffMenu, client, 60);
}

public int noMenuHandler(Handle menu, MenuAction action, int client, int item) {  }

public void OnClientPostAdminCheck(int client) {
	g_bIsVip[client] = false;
	char cleanUp[256];
	Format(cleanUp, sizeof(cleanUp), "DELETE FROM tVip WHERE enddate < NOW();");
	SQL_TQuery(g_DB, SQLErrorCheckCallback, cleanUp);
	
	loadVip(client);
}

public void loadVip(int client) {
	char playerid[20];
	GetClientAuthId(client, AuthId_Steam2, playerid, sizeof(playerid));
	if (StrContains(playerid, "STEAM_") != -1)
		strcopy(playerid, sizeof(playerid), playerid[8]);
	char isVipQuery[1024];
	Format(isVipQuery, sizeof(isVipQuery), "SELECT vip_level FROM tVip WHERE playerid = '%s' AND enddate > NOW();", playerid);
	
	//Pass the userid to prevent assigning flags to a wrong client
	SQL_TQuery(g_DB, SQLCheckVIPQuery, isVipQuery, GetClientUserId(client));
}

public void SQLCheckVIPQuery(Handle owner, Handle hndl, const char[] error, any data) {
	int client = GetClientOfUserId(data);
	
	Action result = Plugin_Continue;
	Call_StartForward(g_hForward_OnClientLoadedPre);
	Call_PushCell(client);
	Call_Finish(result);

	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return;
	}
	
	//Check if the user is still ingame
	if (isValidClient(client)) {
		while (SQL_FetchRow(hndl)) {
			int level = SQL_FetchInt(hndl, 0);
			setFlags(client, level);
		}
	}
	
	Call_StartForward(g_hForward_OnClientLoadedPost);
	Call_PushCell(client);
	Call_Finish();
}

public void setFlags(int client, int level) {
	g_bIsVip[client] = true;
	for (int i = 0; i < level; i++)
	SetUserFlagBits(client, GetUserFlagBits(client) | (1 << g_iFlags[i]));
}

public void OnRebuildAdminCache(AdminCachePart part) {
	if (part == AdminCache_Admins)
		reloadVIPs();
}

public void reloadVIPs() {
	for (int i = 1; i < MAXPLAYERS; i++) {
		if (!isValidClient(i))
			continue;
		loadVip(i);
	}
}

public void deleteVip(char[] playerid) {
	char deleteVipQuery[512];
	Format(deleteVipQuery, sizeof(deleteVipQuery), "DELETE FROM tVip WHERE playerid = '%s';", playerid);
	SQL_TQuery(g_DB, SQLErrorCheckCallback, deleteVipQuery);
}

public void listUsers(int client) {
	char listVipsQuery[1024];
	Format(listVipsQuery, sizeof(listVipsQuery), "SELECT playername,playerid FROM tVip WHERE enddate > NOW();");
	SQL_TQuery(g_DB, SQLListVIPsQuery, listVipsQuery, client);
}

public void SQLListVIPsQuery(Handle owner, Handle hndl, const char[] error, any data) {
	int client = data;
	Menu menuToRemoveClients = CreateMenu(listVipsMenuHandler);
	SetMenuTitle(menuToRemoveClients, "All VIPs on this Server");
	while (SQL_FetchRow(hndl)) {
		char playerid[20];
		char playername[MAX_NAME_LENGTH + 8];
		SQL_FetchString(hndl, 0, playername, sizeof(playername));
		SQL_FetchString(hndl, 1, playerid, sizeof(playerid));
		AddMenuItem(menuToRemoveClients, playerid, playername);
	}
	DisplayMenu(menuToRemoveClients, client, 60);
}

public int listVipsMenuHandler(Handle menu, MenuAction action, int client, int item) {
	if (action == MenuAction_Select) {
		char cValue[20];
		GetMenuItem(menu, item, cValue, sizeof(cValue));
		char detailsQuery[512];
		Format(detailsQuery, sizeof(detailsQuery), "SELECT playername,playerid,enddate,timestamp,admin_playername,admin_playerid,vip_level FROM tVip WHERE playerid = '%s';", cValue);
		SQL_TQuery(g_DB, SQLDetailsQuery, detailsQuery, client);
	}
}

public void SQLDetailsQuery(Handle owner, Handle hndl, const char[] error, any data) {
	int client = data;
	Menu detailsMenu = CreateMenu(detailsMenuHandler);
	bool hasData = false;
	while (SQL_FetchRow(hndl) && !hasData) {
		char playerid[20];
		char playername[MAX_NAME_LENGTH + 8];
		char startDate[128];
		char endDate[128];
		char adminname[MAX_NAME_LENGTH + 8];
		char adminplayerid[20];
		int level;
		SQL_FetchString(hndl, 0, playername, sizeof(playername));
		SQL_FetchString(hndl, 1, playerid, sizeof(playerid));
		SQL_FetchString(hndl, 2, endDate, sizeof(endDate));
		SQL_FetchString(hndl, 3, startDate, sizeof(startDate));
		SQL_FetchString(hndl, 4, adminname, sizeof(adminname));
		SQL_FetchString(hndl, 5, adminplayerid, sizeof(adminplayerid));
		level = SQL_FetchInt(hndl, 6);
		
		char title[64];
		Format(title, sizeof(title), "Details: %s", playername);
		SetMenuTitle(detailsMenu, title);
		
		char playeridItem[64];
		Format(playeridItem, sizeof(playeridItem), "STEAM_ID: %s", playerid);
		AddMenuItem(detailsMenu, "x", playeridItem, ITEMDRAW_DISABLED);
		
		char endItem[64];
		Format(endItem, sizeof(endItem), "Ends: %s", endDate);
		AddMenuItem(detailsMenu, "x", endItem, ITEMDRAW_DISABLED);
		
		char levelItem[64];
		Format(levelItem, sizeof(levelItem), "Level: %i", level);
		AddMenuItem(detailsMenu, "x", levelItem, ITEMDRAW_DISABLED);
		
		char startItem[64];
		Format(startItem, sizeof(startItem), "Started: %s", startDate);
		AddMenuItem(detailsMenu, "x", startItem, ITEMDRAW_DISABLED);
		
		char adminNItem[64];
		Format(adminNItem, sizeof(adminNItem), "By Admin: %s", adminname);
		AddMenuItem(detailsMenu, "x", adminNItem, ITEMDRAW_DISABLED);
		
		char adminIItem[64];
		Format(adminIItem, sizeof(adminIItem), "Admin ID: %s", adminplayerid);
		AddMenuItem(detailsMenu, "x", adminIItem, ITEMDRAW_DISABLED);
		
		hasData = true;
	}
	DisplayMenu(detailsMenu, client, 60);
}

public int detailsMenuHandler(Handle menu, MenuAction action, int client, int item) {
	if (action == MenuAction_Select) {
		
	} else if (action == MenuAction_Cancel) {
		listUsers(client);
	}
}

stock bool isValidClient(int client) {
	return (1 <= client <= MaxClients && IsClientInGame(client));
}

stock bool isVipCheck(int client) {
	return CheckCommandAccess(client, "sm_amIVip", (1 << g_iFlag), true);
}

public void SQLErrorCheckCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if (!StrEqual(error, ""))
		LogError(error);
} 