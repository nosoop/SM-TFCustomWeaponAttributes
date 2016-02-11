/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>

#include <tf2_stocks>
#include <tf2_morestocks>

#pragma newdecls required

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
    name = "[TF2] Sapper Cooldown Test",
    author = "nosoop",
    description = "Description!",
    version = PLUGIN_VERSION,
    url = "localhost"
}

float g_flClientSapLockTime[MAXPLAYERS+1];

public void OnPluginStart() {
	HookEvent("player_sapped_object", OnObjectSapped);
	HookEvent("post_inventory_application", OnPlayerLoadoutRefresh);
	
	for (int i = MaxClients; i > 0; --i) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	g_flClientSapLockTime[client] = 0.0;
	
	// TODO fully prevent client from switching weapon
	SDKHook(client, SDKHook_WeaponCanSwitchTo, OnSapperSwitch);
}

public void OnPlayerLoadoutRefresh(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	g_flClientSapLockTime[client] = 0.0;
}

public Action OnSapperSwitch(int client, int weapon) {
	if (weapon == GetPlayerWeaponSlot(client, view_as<int>(TF2ItemSlot_Sapper))
			&& g_flClientSapLockTime[client] > GetGameTime()) {
		EmitGameSoundToClient(client, "Player.DenyWeaponSelection");
		
		TF_HudNotifyCustom(client, "obj_status_sapper", TF2_GetClientTeam(client),
				"Sapper is disabled for another %d seconds.",
				RoundToCeil(g_flClientSapLockTime[client] - GetGameTime()));
		
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void OnObjectSapped(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("userid"));
	// int buildingtype = event.GetInt("object");
	// int sapperid = event.GetInt("sapperid");
	
	int sapper = GetPlayerWeaponSlot(attacker, view_as<int>(TF2ItemSlot_Sapper));
	
	SetEntPropFloat(sapper, Prop_Data, "m_flNextPrimaryAttack", GetGameTime() + 10.0);
	
	ForceSwitchFromSecondaryWeapon(attacker);
	SetSapperTimer(attacker, 10.0);
}

void ForceSwitchFromSecondaryWeapon(int client) {
	if (IsValidEntity(GetPlayerWeaponSlot(client, view_as<int>(TF2ItemSlot_Melee)))) {
		ClientCommand(client, "slot3");
	} else if (IsValidEntity(GetPlayerWeaponSlot(client, view_as<int>(TF2ItemSlot_Primary)))) {
		ClientCommand(client, "slot1");
	} else {
		// we can't really control it
	}
}

void SetSapperTimer(int client, float cooldown) {
	float regenTime = GetGameTime() + cooldown;
	
	int sapper = GetPlayerWeaponSlot(client, view_as<int>(TF2ItemSlot_Sapper));
	SetEntPropFloat(sapper, Prop_Send, "m_flEffectBarRegenTime", regenTime);
	g_flClientSapLockTime[client] = regenTime;
	
	DataPack pack;
	CreateDataTimer(cooldown, Timer_OnSapperTimerDone, pack, TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteCell(GetClientUserId(client));
	pack.WriteFloat(regenTime);
}

public Action Timer_OnSapperTimerDone(Handle timer, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	float regenTime = pack.ReadFloat();
	
	if (g_flClientSapLockTime[client] == regenTime && IsPlayerAlive(client)) {
		EmitGameSoundToClient(client, "TFPlayer.ReCharged");
	}
	return Plugin_Handled;
}

stock void TF_HudNotifyCustom(int client, const char[] icon, TFTeam team, const char[] format,
		any ...) {
	if (client <= 0 || client > MaxClients) {
		ThrowError("Invalid client index %d", client);
	} else if (!IsClientInGame(client)) {
		ThrowError("Client %d is not in game", client);
	}
	
	char buffer[256];
	VFormat(buffer, sizeof(buffer), format, 5);
	
	TF_HudNotifyCustomParams(view_as<BfWrite>(StartMessageOne("HudNotifyCustom", client)),
			buffer, icon, team);
}

stock void TF_HudNotifyCustomParams(BfWrite bitbuf, const char[] message, const char[] icon,
		TFTeam team) {
	bitbuf.WriteString(message);
	bitbuf.WriteString(icon);
	bitbuf.WriteByte(view_as<int>(team));
	
	EndMessage();
}
