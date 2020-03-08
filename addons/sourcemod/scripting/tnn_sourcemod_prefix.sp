public OnPluginStart() 
{ 
	HookUserMessage(GetUserMessageId("TextMsg"), OnTextMsg, true); 
} 

public Action OnTextMsg(UserMsg msg_id, Protobuf hUserMsg, const int[] iClients, int iNumClients, bool bReliable, bool bInit)
{
	if (!bReliable || hUserMsg.ReadInt("msg_dst") != 3) 
		return Plugin_Continue; 
        
	char[] sBuffer = new char[PLATFORM_MAX_PATH]; 
	hUserMsg.ReadString("params", sBuffer, PLATFORM_MAX_PATH, 0); 

	if (sBuffer[0] == '[' && sBuffer[1] == 'S' && sBuffer[2] == 'M' && sBuffer[3] == ']') 
		ReplaceString(sBuffer, PLATFORM_MAX_PATH, "[SM]", "");
	else if (StrContains(sBuffer, "[MCE]") != -1)
		ReplaceString(sBuffer, PLATFORM_MAX_PATH, "[MCE]", "");
	else if (StrContains(sBuffer, "[CSGOTOKENS.COM]") != -1)
		ReplaceString(sBuffer, PLATFORM_MAX_PATH, "[CSGOTOKENS.COM]", "");
	else if (StrContains(sBuffer, "[SourceComms++]") != -1)
		ReplaceString(sBuffer, PLATFORM_MAX_PATH, "[SourceComms++]", "");
	else if (StrContains(sBuffer, "[SourceBans++]") != -1)
		ReplaceString(sBuffer, PLATFORM_MAX_PATH, "[SourceBans++]", "");
	else if (StrContains(sBuffer, "[SMACBANS]") != -1)
		ReplaceString(sBuffer, PLATFORM_MAX_PATH, "[SMACBANS]", "");
	else if (StrContains(sBuffer, "[Anti-Micspam]") != -1)
		ReplaceString(sBuffer, PLATFORM_MAX_PATH, "[Anti-Micspam]", "");
	else if (StrContains(sBuffer, "[Store]") != -1)
		ReplaceString(sBuffer, PLATFORM_MAX_PATH, "[Store]", "");
	else
		return Plugin_Continue; 
		
	DataPack hPack = new DataPack(); 
	CreateDataTimer(0.0, prefixChange, hPack, TIMER_FLAG_NO_MAPCHANGE);
	hPack.WriteCell(iNumClients); 
    
	for (int i = 0; i < iNumClients; ++i) 
		hPack.WriteCell(iClients[i]); 
    
	hPack.WriteCell(strlen(sBuffer)); 
	hPack.WriteString(sBuffer); 
	hPack.Reset(); 
	return Plugin_Handled; 
} 

public Action prefixChange(Handle timer, DataPack hPack)
{ 
	int iTotal = hPack.ReadCell(); 
	int[] iPlayers = new int[iTotal]; 
	int client, players_count; 

	for (int i = 0; i < iTotal; ++i) 
	{ 
		client = hPack.ReadCell(); 

		if (IsClientInGame(client)) 
			iPlayers[players_count++] = client; 
	} 

	iTotal = players_count; 

	if (iTotal >= 1) 
	{
		Handle pb = StartMessage("TextMsg", iPlayers, iTotal, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS); 
		PbSetInt(pb, "msg_dst", 3); 
	
		int buffer_size = hPack.ReadCell() + 30; 
		char[] buffer = new char[buffer_size]; 
		
		hPack.ReadString(buffer, buffer_size);
		Format(buffer, buffer_size, " [\x0BNexusLeague.gg\x01]%s", buffer);
	
		PbAddString(pb, "params", buffer); 
		PbAddString(pb, "params", NULL_STRING); 
		PbAddString(pb, "params", NULL_STRING); 
		PbAddString(pb, "params", NULL_STRING); 
		PbAddString(pb, "params", NULL_STRING); 
		EndMessage(); 
	}
	delete hPack;
}