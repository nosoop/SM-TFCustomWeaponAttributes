#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <tf2_stocks>

#include <tf_custom_attributes>
#include <tf_ontakedamage>

#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "[TF2] Custom Weapon Attribute: Minicrits on Bleed",
	author = "nosoop",
	description = "Weapon damage is minicrits if the victim is bleeding.",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop/SM-TFCustomWeaponAttributes/tree/custattr-conv"
}

#define ATTR_MINICRIT_BLEED "minicrits on bleed"

public Action TF2_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage,
		int &damagetype, int &weapon, float damageForce[3], float damagePosition[3],
		int damagecustom, CritType &critType) {
	if (critType) {
		return Plugin_Continue;
	}
	
	if (!TF2_IsPlayerInCondition(victim, TFCond_Bleeding)) {
		return Plugin_Continue;
	}
	
	KeyValues attr = TF2CustAttr_GetAttributeKeyValues(weapon);
	if (attr) {
		if (!!attr.GetNum(ATTR_MINICRIT_BLEED)) {
			critType = CritType_MiniCrit;
		}
		delete attr;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}
