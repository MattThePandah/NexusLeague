char pauseMode[128];
char steamid[64];

MatchTeam teamPaused;

Handle pauseTimerHandler;

public bool Pauseable() {
  return g_GameState >= Get5State_KnifeRound && g_PausingEnabledCvar.BoolValue;
}

public Action Command_TechPause(int client, int args) {
  if (!g_AllowTechPauseCvar.BoolValue || !Pauseable() || IsPaused()) {
    return Plugin_Handled;
  }

  g_InExtendedPause = true;

  if (client == 0) {
    Pause();
    Get5_MessageToAll("%t", "AdminForceTechPauseInfoMessage");
    return Plugin_Handled;
  }

  Pause();
  Get5_MessageToAll("%t", "MatchTechPausedByTeamMessage", client);

  return Plugin_Handled;
}

public Action Command_Pause(int client, int args)
{
  if (!Pauseable() || IsPaused()) {
    return Plugin_Stop;
  }

  int currentTime = GetTime();
  if (g_cooldownTimes[client] != -1 && g_cooldownTimes[client] > currentTime)
  {
    return Plugin_Handled;
  }
  g_cooldownTimes[client] = currentTime + 15;

  GetConVarString(g_PauseModeCvar, pauseMode, sizeof(pauseMode));

  if (StrEqual(pauseMode, "Faceit", false)) {
    MatchTeam team = CSTeamToMatchTeam(GetClientTeam(client));
    GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
    int maxPauseTime = g_MaxPauseTimeCvar.IntValue;

    if (maxPauseTime> 0 && g_TeamPauseTimeUsed[team] >= maxPauseTime) {
      Get5_Message(client, "You have no more timeout time remaining.");
      return Plugin_Handled;
    }

    ServerCommand("mp_pause_match");
    teamPaused = team;
    
    int timeLeft = maxPauseTime - g_TeamPauseTimeUsed[team];
    int minutes = timeLeft / 60;
    int seconds = timeLeft % 60;

    int teamIndex = -1;
    int index = -1;

    while ((index = FindEntityByClassname(index, "cs_team_manager")) != -1) {
      int teamNum = GetEntProp(index, Prop_Send, "m_iTeamNum");
      int csTeam = MatchTeamToCSTeam(team);
      if (teamNum == csTeam) {
        teamIndex = index;
      }
    }

    char teamName[32];
    GetEntPropString(teamIndex, Prop_Send, "m_szClanTeamname", teamName, 32);
    Get5_MessageToAll("%s has %i minute(s) %i second(s) left for pauses.", teamName, minutes, seconds);

    pauseTimerHandler = CreateTimer(1.0, Timer_PauseTimeCheck, team, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Handled;

  } else if (StrEqual(pauseMode, "Valve", false)) {
    // Not sure what else this state can do. ¯\_(ツ)_/¯
    g_TeamReadyForUnpause[MatchTeam_Team1] = false;
    g_TeamReadyForUnpause[MatchTeam_Team2] = false;
    FakeClientCommandEx(client,"callvote StartTimeout");
  } else {
    MatchTeam team = GetClientMatchTeam(client);
    int maxPauses = g_MaxPausesCvar.IntValue;
    char pausePeriodString[32];

    if (g_ResetPausesEachHalfCvar.BoolValue) {
      Format(pausePeriodString, sizeof(pausePeriodString), " %t", "PausePeriodSuffix");
    }
    if (maxPauses > 0 && g_TeamPausesUsed[team] >= maxPauses && IsPlayerTeam(team)) {
      Get5_Message(client, "%t", "MaxPausesUsedInfoMessage", maxPauses, pausePeriodString);
      return Plugin_Handled;
    }

    g_TeamReadyForUnpause[MatchTeam_Team1] = false;
    g_TeamReadyForUnpause[MatchTeam_Team2] = false;
    Pause(g_FixedPauseTimeCvar.IntValue, MatchTeamToCSTeam(team));

    if (IsPlayer(client)) {
      Get5_MessageToAll("%t", "MatchPausedByTeamMessage", client);
    }
    if (IsPlayerTeam(team)) {
      g_TeamPausesUsed[team]++;
      pausePeriodString = "";
      if (g_ResetPausesEachHalfCvar.BoolValue) {
        Format(pausePeriodString, sizeof(pausePeriodString), " %t", "PausePeriodSuffix");
      }

      if (g_MaxPausesCvar.IntValue > 0) {
        int pausesLeft = g_MaxPausesCvar.IntValue - g_TeamPausesUsed[team];
        if (pausesLeft == 1 && g_MaxPausesCvar.IntValue > 0) {
          Get5_MessageToAll("%t", "OnePauseLeftInfoMessage", g_FormattedTeamNames[team], pausesLeft,pausePeriodString);
        } else if (g_MaxPausesCvar.IntValue > 0) {
          Get5_MessageToAll("%t", "PausesLeftInfoMessage", g_FormattedTeamNames[team], pausesLeft,pausePeriodString);
        }
      }
    }

    return Plugin_Handled;
  }
  
  return Plugin_Handled;
}

public Action Timer_PauseTimeCheck(Handle timer, int data) {
  if (!Pauseable() || !IsPaused() || g_FixedPauseTimeCvar.BoolValue) {
    return Plugin_Stop;
  }
  GetConVarString(g_PauseModeCvar, pauseMode, sizeof(pauseMode));

  if (StrEqual(pauseMode, "Faceit", false)) {
    MatchTeam team = view_as<MatchTeam>(data);
    int maxPauseTime = g_MaxPauseTimeCvar.IntValue;
    int timeLeft = maxPauseTime - g_TeamPauseTimeUsed[team];
    int minutes = timeLeft / 60;
    int seconds = timeLeft % 60;
    if (InFreezeTime()) {
      g_TeamPauseTimeUsed[team]++;

      int teamIndex = -1;
      int index = -1;

      while ((index = FindEntityByClassname(index, "cs_team_manager")) != -1) {
        int teamNum = GetEntProp(index, Prop_Send, "m_iTeamNum");
        int csTeam = MatchTeamToCSTeam(team);
        if (teamNum == csTeam) {
          teamIndex = index;
        }
      }

      char teamName[32];
      GetEntPropString(teamIndex, Prop_Send, "m_szClanTeamname", teamName, 32);
      if (timeLeft % 30 == 0 && timeLeft != maxPauseTime) {
        Get5_MessageToAll("%s has %i minute(s) %i second(s) left for pauses.", teamName, minutes, seconds);
        return Plugin_Handled;
      }

      if (timeLeft == 10) {
        Get5_MessageToAll("%s has %i second(s) left for pauses", teamName, seconds);
        return Plugin_Handled;
      }
      
      if (timeLeft <= 0) {
        Get5_MessageToAll("%s has used all the pause time.", teamName);
        ServerCommand("mp_unpause_match");
        return Plugin_Stop;
      }
    }

    return Plugin_Continue;
  }

  return Plugin_Handled;
}

public Action Command_Unpause(int client, int args) {
  if (!IsPaused()) {
    return Plugin_Stop;
  }

  int currentTime = GetTime();
  if (g_cooldownTimes[client] != -1 && g_cooldownTimes[client] > currentTime)
  {
    return Plugin_Handled;
  }
  g_cooldownTimes[client] = currentTime + 30;


  GetConVarString(g_PauseModeCvar, pauseMode, sizeof(pauseMode));

  if (StrEqual(pauseMode, "Faceit", false)) {
    MatchTeam team = GetClientMatchTeam(client);
    int teamIndex = -1;
    int index = -1;

    while ((index = FindEntityByClassname(index, "cs_team_manager")) != -1) {
      int teamNum = GetEntProp(index, Prop_Send, "m_iTeamNum");
      int csTeam = MatchTeamToCSTeam(team);
      if (teamNum == csTeam) {
        teamIndex = index;
      }
    }

    char teamName[32];
    GetEntPropString(teamIndex, Prop_Send, "m_szClanTeamname", teamName, 32);
    int maxPauseTime = g_MaxPauseTimeCvar.IntValue;
    int timeLeft = maxPauseTime - g_TeamPauseTimeUsed[team];
    int minutes = timeLeft / 60;
    int seconds = timeLeft % 60;

    if (team == teamPaused) {
      ServerCommand("mp_unpause_match");
      KillTimer(pauseTimerHandler);
      Get5_MessageToAll("%s has %i minute(s) %i second(s) left for pauses", teamName, minutes, seconds);
    }

    return Plugin_Handled;

  } else if (StrEqual(pauseMode, "Valve", false)) {
    MatchTeam team = GetClientMatchTeam(client);
    g_TeamReadyForUnpause[team] = true;
    
    if (g_TeamReadyForUnpause[MatchTeam_Team1] && g_TeamReadyForUnpause[MatchTeam_Team2]) {
      if (GameRules_GetProp("m_bTerroristTimeOutActive") == 1){
        GameRules_SetPropFloat("m_flTerroristTimeOutRemaining", 0.0);
      } else if (GameRules_GetProp("m_bCTTimeOutActive") == 1) {
        GameRules_SetPropFloat("m_flCTTimeOutRemaining", 0.0);
      }

      if (IsPlayer(client)) {
        Get5_MessageToAll("%t", "MatchUnpauseInfoMessage", client);
      }
    } else if (g_TeamReadyForUnpause[MatchTeam_Team1] && !g_TeamReadyForUnpause[MatchTeam_Team2]) {
      Get5_MessageToAll("%t", "WaitingForUnpauseInfoMessage", g_FormattedTeamNames[MatchTeam_Team1],g_FormattedTeamNames[MatchTeam_Team2]);
    } else if (!g_TeamReadyForUnpause[MatchTeam_Team1] && g_TeamReadyForUnpause[MatchTeam_Team2]) {
      Get5_MessageToAll("%t", "WaitingForUnpauseInfoMessage", g_FormattedTeamNames[MatchTeam_Team2],g_FormattedTeamNames[MatchTeam_Team1]);
    }

    return Plugin_Handled;
  } else {
    if (client == 0) {
      Unpause();
      Get5_MessageToAll("%t", "AdminForceUnPauseInfoMessage");
      return Plugin_Handled;
    }

    if (g_FixedPauseTimeCvar.BoolValue && !g_InExtendedPause) {
      return Plugin_Handled;
    }

    MatchTeam team = GetClientMatchTeam(client);
    g_TeamReadyForUnpause[team] = true;

    if (g_TeamReadyForUnpause[MatchTeam_Team1] && g_TeamReadyForUnpause[MatchTeam_Team2]) {
      Unpause();
      if (IsPlayer(client)) {
        Get5_MessageToAll("%t", "MatchUnpauseInfoMessage", client);
      }
    } else if (g_TeamReadyForUnpause[MatchTeam_Team1] && !g_TeamReadyForUnpause[MatchTeam_Team2]) {
      Get5_MessageToAll("%t", "WaitingForUnpauseInfoMessage", g_FormattedTeamNames[MatchTeam_Team1],
                        g_FormattedTeamNames[MatchTeam_Team2]);
    } else if (!g_TeamReadyForUnpause[MatchTeam_Team1] && g_TeamReadyForUnpause[MatchTeam_Team2]) {
      Get5_MessageToAll("%t", "WaitingForUnpauseInfoMessage", g_FormattedTeamNames[MatchTeam_Team2],
                        g_FormattedTeamNames[MatchTeam_Team1]);
    }
  }

  return Plugin_Handled;
}