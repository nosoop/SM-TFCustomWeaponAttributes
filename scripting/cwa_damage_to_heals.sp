/**
 * [TF2] Custom Weapon Attribute:  Damage To Heals
 * Damage dealt heals the player.
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdktools>

#include <stocksoup/tf/player>
#include <tf_custom_attributes>

#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "[TF2] Custom Weapon Attribute: Damage To Heals",
	author = "nosoop",
	description = "Heals the same amount as damage dealt.",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop/SM-TFCustomWeaponAttributes"
}

#define ATTR_DAMAGE_HEAL_RATE "damage to heals"

public void OnPluginStart() {
	HookEvent("player_hurt", OnPlayerHurt);
}

public void OnPlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	
	if (attacker && victim) {
		int amount = event.GetInt("damageamount");
		
		int hActiveWeapon = GetEntPropEnt(attacker, Prop_Data, "m_hActiveWeapon");
		
		KeyValues attr = TF2CustAttr_GetAttributeKeyValues(hActiveWeapon);
		if (attr) {
			float flHealRatio = attr.GetFloat(ATTR_DAMAGE_HEAL_RATE);
			delete attr;
			
			TF2_HealPlayer(attacker, RoundFloat(amount * flHealRatio), .notify = true);
		}
	}
}
