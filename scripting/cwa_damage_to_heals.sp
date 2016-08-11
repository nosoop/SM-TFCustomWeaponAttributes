/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>
#include <customweaponstf>

#pragma newdecls required

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
    name = "[TF2] Custom Weapon Attribute: Damage To Heals",
    author = "nosoop",
    description = "Heals the same amount as damage dealt.",
    version = PLUGIN_VERSION,
    url = "https://github.com/nosoop/SM-TFCustomWeaponAttributes"
}

#define CW2_PLUGIN_NAME "custom-weapon-soup"
#define ATTR_MINICRIT_BLEED "damage to heals"

ArrayList g_DamageToHealsWeapons;

public void OnPluginStart() {
	g_DamageToHealsWeapons = new ArrayList();
	
	HookEvent("player_hurt", OnPlayerHurt);
}

public Action CustomWeaponsTF_OnAddAttribute(int weapon, int client, const char[] attrib,
		const char[] plugin, const char[] value) {
	if (StrEqual(plugin, CW2_PLUGIN_NAME, false) && StrEqual(attrib, ATTR_MINICRIT_BLEED)) {
		g_DamageToHealsWeapons.Push(weapon);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void OnEntityDestroyed(int entity) {
	int index;
	if ((index = g_DamageToHealsWeapons.FindValue(entity)) != -1) {
		g_DamageToHealsWeapons.Erase(index);
	}
}

public void OnPlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	
	if (attacker && victim) {
		int amount = event.GetInt("damageamount");
		
		int hActiveWeapon = GetEntPropEnt(attacker, Prop_Data, "m_hActiveWeapon");
		
		if (g_DamageToHealsWeapons.FindValue(hActiveWeapon) != -1) {
			TF2_HealPlayer(attacker, amount, false, true);
		}
	}
}

/**
 * Attempts to heal player by the specified amount.
 
 * @return true if the player was (over) healed, false if no heals were applied
 */
bool TF2_HealPlayer(int client, int nHealAmount, bool overheal = false, bool notify = false) {
	if (IsPlayerAlive(client)) {
		int nHealth = GetClientHealth(client);
		int nMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send,
				"m_iMaxHealth", _, client);
		
		// cap heals to max health
		if (!overheal && nHealAmount > nMaxHealth - nHealth) {
			nHealAmount = nMaxHealth - nHealth;
		}
		
		if (nHealAmount > 0) {
			SetEntityHealth(client, nHealth + nHealAmount);
			
			// player health HUD notification
			if (notify) {
				Event event = CreateEvent("player_healonhit");
				if (event) {
					event.SetInt("amount", nHealAmount);
					event.SetInt("entindex", client);
					
					event.Fire();
				}
			}
			
			return true;
		}
	}
	return false;
}