/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>

#include <tf2>
#include <customweaponstf>
#include <stocksoup/log_server>
#include <tf2_morestocks>
#include <tf2attributes>

#pragma newdecls required

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
    name = "Custom Weapon Attributes: Saxton Spinach",
    author = "nosoop",
    description = "Custom attributes for the 'Saxton Spinach' weapon idea",
    version = PLUGIN_VERSION,
    url = "localhost"
}

#define CW2_PLUGIN_NAME "custom-weapon-soup-saxton-spinach"

#define ATTR_SCOUT_BONK_OVERRIDE "scout bonk override"
#define ATTR_FIRING_SPEED_BONUS "firing rate multiplier on use"
#define ATTR_RELOAD_SPEED_BONUS "reload speed multiplier on use"
#define ATTR_BONK_EFFECT_DURATION "scout bonk effect duration"

float g_flModAttackSpeed[MAXPLAYERS+1], g_flModNextAttack[MAXPLAYERS+1];

public Action CustomWeaponsTF_OnAddAttribute(int weapon, int client, const char[] attrib,
		const char[] plugin, const char[] value) {
	// Attach attribute if desired
	if (StrEqual(plugin, CW2_PLUGIN_NAME, false)) {
		
		// I'm not at all fond of how CW2 works.  That's no secret.
		// I should make my own custom attribute plugin.
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void TF2_OnConditionAdded(int client, TFCond condition) {
	if (condition == TFCond_Bonked) {
		KeyValues customWeapon = view_as<KeyValues>(
				CusWepsTF_GetClientWeapon(client, view_as<int>(TF2ItemSlot_Secondary)));
		
		LogServer("keyvalue handle: %d", customWeapon);
		
		if (!customWeapon) {
			return;
		}
		
		customWeapon.Rewind();
		
		if (!customWeapon.JumpToKey("attributes", false)) {
			return;
		}
		
		if (GetAttributeNum(customWeapon, ATTR_SCOUT_BONK_OVERRIDE) == 0) {
			return;
		}
		
		TF2_RemoveCondition(client, TFCond_Bonked);
		
		float flDuration = GetAttributeFloat(customWeapon, ATTR_BONK_EFFECT_DURATION, 10.0);
		
		TF2_AddCondition(client, TFCond_SpeedBuffAlly, flDuration);
		
		// custom mod fire rate because the valve-provided attribute can't reset itself
		float flFiringRateMod = GetAttributeFloat(customWeapon, ATTR_FIRING_SPEED_BONUS, 1.25);
		g_flModAttackSpeed[client] = flFiringRateMod;
		SDKHook(client, SDKHook_PostThink, OnPlayerModFireRate);
		
		// reload is fine though
		float flReloadRateMod = GetAttributeFloat(customWeapon, ATTR_RELOAD_SPEED_BONUS, 1.25);
		TF2Attrib_SetByName(client, "Reload time decreased", 1.0 / flReloadRateMod);
		
		LogServer("Firing rate %f, reload rate %f", flFiringRateMod, flReloadRateMod);
		
		CreateTimer(flDuration, OnSpinachEffectExpired, GetClientUserId(client),
				TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action OnSpinachEffectExpired(Handle timer, int userid) {
	int client = GetClientOfUserId(userid);
	
	if (client) {
		if (IsPlayerAlive(client)) {
		}
		
		SDKUnhook(client, SDKHook_PostThink, OnPlayerModFireRate);
		TF2Attrib_RemoveByName(client, "Reload time decreased");
		g_flModAttackSpeed[client] == 0.0;
		LogServer("Removed effects from %N", client);
	}
	return Plugin_Handled;
}

float GetAttributeFloat(KeyValues customWeapon, const char[] attrib, float defaultValue = 0.0) {
	char attrKey[64];
	Format(attrKey, sizeof(attrKey), "%s/value", attrib);
	return customWeapon.GetFloat(attrKey, defaultValue);
}

int GetAttributeNum(KeyValues customWeapon, const char[] attrib, int defaultValue = 0) {
	char attrKey[64];
	Format(attrKey, sizeof(attrKey), "%s/value", attrib);
	LogServer("key %s", attrKey);
	return customWeapon.GetNum(attrKey, defaultValue);
}

public void OnPlayerModFireRate(int client) {
	if (g_flModAttackSpeed[client] > 0.0 && IsPlayerAlive(client)) {
		int hActiveWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
		
		float flNextAttack = GetEntPropFloat(hActiveWeapon, Prop_Data,
				"m_flNextPrimaryAttack");
		
		if (g_flModNextAttack[client] < flNextAttack) {
			float flModifier = g_flModAttackSpeed[client];
			
			float duration = flNextAttack - GetGameTime();
			float flModNextAttack = GetGameTime() + (duration / flModifier);
			
			SetEntPropFloat(hActiveWeapon, Prop_Data, "m_flNextPrimaryAttack", flModNextAttack);
			
			g_flModNextAttack[client] = flModNextAttack;
			
			SetEntPropFloat(client, Prop_Send, "m_flPlaybackRate", flModifier);
		}
	}
}