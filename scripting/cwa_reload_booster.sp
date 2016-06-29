/**
 * [TF2] Custom Weapon Attribute: Busted Booster
 * 
 * Implements the custom buff effect for the Busted Booster.
 * It was actually pretty fun trying to figure out how to replace the buff.
 */
#pragma semicolon 1
#include <sourcemod>

#include <tf2_stocks>
#include <sdkhooks>
#include <tf2attributes>
#include <customweaponstf>

// #include <stocksoup/log_server>

#pragma newdecls required

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
    name = "[TF2] Custom Weapon Attribute: Busted Booster",
    author = "nosoop",
    description = "Provides the attributes for the Busted Booster custom weapon.",
    version = PLUGIN_VERSION,
    url = "https://github.com/nosoop"
}

// The Busted Booster replaces the Batallion's Backup -- the Buff's cond makes the weapon flicker
#define BUFF_TYPE_OVERRIDE TFCond_DefenseBuffed
#define BUFF_ITEM_DEFINDEX 226

#define BUFF_ATTACK_INCREASE 

// sm_custom_addattribute @me 1 "busted booster deploy effect" "1" "custom-weapon-soup"

#define CW2_PLUGIN_NAME "custom-weapon-soup"
#define ATTR_BUSTED_BOOSTER "busted booster deploy effect"
#define ATTR_PRIMARY_RELOAD_INCREASE "primary reload speed increased"

ArrayList g_BoosterEntities;
ArrayList g_PrimarySpeedEntities;

float g_flBoosterBuffEndTime[MAXPLAYERS+1];


public void OnPluginStart() {
	g_BoosterEntities = new ArrayList();
	g_PrimarySpeedEntities = new ArrayList();
	
	for (int i = MaxClients; i > 0; --i) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
	
	HookEvent("post_inventory_application", OnPlayerLoadoutRefreshed, EventHookMode_Post);
}

public void OnEntityDestroyed(int entity) {
	int index;
	if ((index = g_BoosterEntities.FindValue(entity)) != -1) {
		g_BoosterEntities.Erase(index);
	}
	if ((index = g_PrimarySpeedEntities.FindValue(entity)) != -1) {
		g_PrimarySpeedEntities.Erase(index);
	}
}

public Action CustomWeaponsTF_OnAddAttribute(int weapon, int client, const char[] attrib,
		const char[] plugin, const char[] value) {
	// Attach attribute if desired
	if (StrEqual(plugin, CW2_PLUGIN_NAME, false)) {
		if (StrEqual(attrib, ATTR_BUSTED_BOOSTER)
				&& ((g_BoosterEntities.FindValue(weapon)) == -1))  {
			g_BoosterEntities.Push(weapon);
			return Plugin_Handled;
		} else if (StrEqual(attrib, ATTR_PRIMARY_RELOAD_INCREASE)
				&& ((g_PrimarySpeedEntities.FindValue(weapon)) == -1))  {
			g_PrimarySpeedEntities.Push(weapon);
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public void OnClientPutInServer(int client) {
	g_flBoosterBuffEndTime[client] = 0.0;
	SDKHook(client, SDKHook_PostThink, OnClientPostThink);
}

public void OnPlayerLoadoutRefreshed(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	int hWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
	
	if (g_PrimarySpeedEntities.FindValue(hWeapon) != -1) {
		int hPrimaryWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
		TF2Attrib_SetByName(hPrimaryWeapon, "Reload time decreased", 0.85);
	}
}

/**
 * Checks player buff state.
 * This is the best place to check it, as the condition removal makes it completely invisible to
 * the client.
 */
public void OnClientPostThink(int client) {
	if (TF2_IsPlayerInCondition(client, BUFF_TYPE_OVERRIDE)
			|| g_flBoosterBuffEndTime[client] > GetGameTime()) {
		// If soldier with this weapon in radius, apply reload speed boost
		// If soldier with default buff banner *not* in radius, remove buff bonus
		
		bool bNormalBuff, bBoosterBuff;
		for (int i = MaxClients; i > 0; --i) {
			if (!IsClientInGame(i) || !IsPlayerAlive(i)) {
				continue;
			}
			
			if (TF2_GetClientTeam(i) != TF2_GetClientTeam(client)) {
				continue;
			}
			
			bool bPlayerBuffActive = GetEntProp(i, Prop_Send, "m_bRageDraining") != 0;
			
			int hWeapon = GetPlayerWeaponSlot(i, TFWeaponSlot_Secondary);
			int iDefIndex = GetEntProp(hWeapon, Prop_Send, "m_iItemDefinitionIndex");
			
			// TODO make sure player within buff range
			if (bPlayerBuffActive && IsInBuffRange(client, i)) {
				if (g_BoosterEntities.FindValue(hWeapon) != -1) {
					bBoosterBuff = true;
				} else if (iDefIndex == BUFF_ITEM_DEFINDEX) {
					bNormalBuff = true;
				}
			}
		}
		
		if (!bNormalBuff) {
			TF2_RemoveCondition(client, BUFF_TYPE_OVERRIDE);
		}
		
		if (bBoosterBuff) {
			if (GetGameTime() - g_flBoosterBuffEndTime[client] > GetTickInterval()) {
				OnBuffStarted(client);
			}
			
			OnBuffRefreshed(client);
			g_flBoosterBuffEndTime[client] = GetGameTime() + 0.5;
		}
	}
	
	// Check if player buff is over (they died or moved out of buff area)
	// However the buff might end for some other reason, too
	if (g_flBoosterBuffEndTime[client] > 0.0) {
		if (!IsPlayerAlive(client) || GetGameTime() > g_flBoosterBuffEndTime[client]) {
			g_flBoosterBuffEndTime[client] = 0.0;
			
			OnBuffEnded(client);
		}
	}
}

void OnBuffStarted(int client) {
	LogServer("%N started boosting their bust.", client);
	
	TF2Attrib_SetByName(client, "Reload time decreased", GetReloadTimeScalar());
}

// 
float g_flModNextAttack[MAXPLAYERS+1];

void OnBuffRefreshed(int client) {
	int hActiveWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
	float flNextAttack = GetEntPropFloat(hActiveWeapon, Prop_Data,
			"m_flNextPrimaryAttack");
	
	if (g_flModNextAttack[client] < flNextAttack) {
		float flModifier = 1.0 + GetBuffAttackSpeedModifier();
		
		float duration = flNextAttack - GetGameTime();
		float flModNextAttack = GetGameTime()
				+ (duration / flModifier);
		
		SetEntPropFloat(hActiveWeapon, Prop_Data, "m_flNextPrimaryAttack", flModNextAttack);
		
		g_flModNextAttack[client] = flModNextAttack;
		
		SetEntPropFloat(client, Prop_Send, "m_flPlaybackRate", flModifier);
	}
}

void OnBuffEnded(int client) {
	LogServer("%N busted their booster.", client);
	
	TF2Attrib_RemoveByName(client, "Reload time decreased");
}

/* Returns an additive value to modify attack speed */
float GetBuffAttackSpeedModifier() {
	return 0.35;
}

float GetReloadTimeScalar() {
	return 0.65;
}

float g_flBuffRange = 450.0;
bool IsInBuffRange(int client, int other) {
	if (client == other) {
		return true;
	}
	
	float vecClient[3], vecOther[3];
	
	GetClientAbsOrigin(client, vecClient);
	GetClientAbsOrigin(other, vecOther);
	
	return GetVectorDistance(vecClient, vecOther, true) < Pow(g_flBuffRange, 2.0);
}