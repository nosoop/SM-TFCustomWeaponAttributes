/**
 * Custom Weapons Attribute: Exploding Sapper
 * Requested by Karma Charger
 * 5k */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <tf2_stocks>
#include <tf2_morestocks>

#include <tf_custom_attributes>

#include <stocksoup/datapack>
#include <stocksoup/tf/hud_notify>

#include <stocksoup/log_server>
#include <stocksoup/var_strings>

#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "[TF2] Custom Weapon Attribute: Exploding Sapper",
	author = "nosoop",
	description = "Sapper goes boom.",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop/SM-TFCustomWeaponAttributes"
}

#define PARTICLE_NAME_LENGTH 32

// attributes format `${key}=${value}` pairs, space delimited
// valid keys include `damage`, `radius`, `sap_time`, `particle`, and `sound`
#define ATTR_EXPLODING_SAPPER "exploding sapper"

// I can't be bothered to pick an appropriate particle effect
#define SAPPER_DEFAULT_EXPLODING_EFFECT "ghost_appearation"

bool g_bSpewGarbage = false;

public void OnPluginStart() {
	HookEvent("player_sapped_object", OnObjectSapped);
}

public void OnObjectSapped(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("userid"));
	int buildingtype = event.GetInt("object");
	int sapperobj = event.GetInt("sapperid");
	
	char classname[64];
	GetEntityClassname(sapperobj, classname, sizeof(classname));
	
	int building = GetEntPropEnt(sapperobj, Prop_Data, "m_hParent");
	
	DebugToServer("building %d (type %d) being sapped by sapper %d (%s) from player %N",
			building, buildingtype, sapperobj, classname, attacker);
	
	// the sapperobj is the entity attached to the building, not the weapon itself
	int sapper = GetPlayerWeaponSlot(attacker, view_as<int>(TF2ItemSlot_Sapper));
	
	KeyValues attr = TF2CustAttr_GetAttributeKeyValues(sapper);
	if (!attr) {
		DebugToServer("sapper has no custom attributes");
		return;
	}
	
	char explodingSapperProps[512];
	attr.GetString(ATTR_EXPLODING_SAPPER, explodingSapperProps, sizeof(explodingSapperProps));
	delete attr;
	
	if (!explodingSapperProps[0]) {
		// not an exploding sapper
		DebugToServer("not an exploding sapper");
		return;
	}
	
	DebugToServer("is an exploding sapper");
	
	float flSapperDamage = ReadFloatVar(explodingSapperProps, "damage", 216.0);
	float flSapperRadius = ReadFloatVar(explodingSapperProps, "radius", 300.0);
	float flSapperTime = ReadFloatVar(explodingSapperProps, "sap_time", 5.0);
	
	char sapperExplodeParticle[PARTICLE_NAME_LENGTH], sapperExplodeSound[PLATFORM_MAX_PATH];
	ReadStringVar(explodingSapperProps, "particle", sapperExplodeParticle,
			sizeof(sapperExplodeParticle), "ghost_appearation");
	ReadStringVar(explodingSapperProps, "sound", sapperExplodeSound, sizeof(sapperExplodeSound),
			"");
	
	DebugToServer("Sapper info: damage %f, radius %f, particle %s, time %f",
			flSapperDamage, flSapperRadius, sapperExplodeParticle, flSapperTime);
	DebugToServer("... sound %s", sapperExplodeSound);
	
	DataPack sapperData;
	CreateDataTimer(flSapperTime, OnSapperExplode, sapperData);
	
	WritePackClient(sapperData, attacker);
	WritePackEntity(sapperData, sapperobj);
	
	sapperData.WriteFloat(flSapperDamage);
	sapperData.WriteFloat(flSapperRadius);
	
	sapperData.WriteString(sapperExplodeParticle);
	sapperData.WriteString(sapperExplodeSound);
}

public Action OnSapperExplode(Handle timer, DataPack sapperData) {
	sapperData.Reset();
	
	char sapperExplodeParticle[PARTICLE_NAME_LENGTH];
	char sapperExplodeSound[PLATFORM_MAX_PATH];
	
	int attacker = ReadPackClient(sapperData);
	int sapperobj = ReadPackEntity(sapperData);
	
	// attacker left or sapper doesn't exist anymore
	if (!attacker || !IsValidEntity(sapperobj)) {
		return Plugin_Handled;
	}
	
	float flSapperDamage = sapperData.ReadFloat();
	float flSapperRadius = sapperData.ReadFloat();
	sapperData.ReadString(sapperExplodeParticle, sizeof(sapperExplodeParticle));
	sapperData.ReadString(sapperExplodeSound, sizeof(sapperExplodeSound));
	
	DebugToServer("Sapper info: damage %f, radius %f, particle %s",
			flSapperDamage, flSapperRadius, sapperExplodeParticle);
	
	int building = GetEntPropEnt(sapperobj, Prop_Data, "m_hParent");
	
	float vecOrigin[3];
	GetEntPropVector(building, Prop_Data, "m_vecOrigin", vecOrigin);
	
	int bomb = TF2_CreateGenericBomb(vecOrigin, flSapperDamage, flSapperRadius,
			sapperExplodeParticle, sapperExplodeSound);
	SDKHooks_TakeDamage(bomb, attacker, attacker, 5.0);
	AcceptEntityInput(bomb, "Detonate");
	AcceptEntityInput(bomb, "Kill");
	
	DebugToServer("Sapper exploded?");
	
	if (IsValidEntity(sapperobj)) {
		AcceptEntityInput(sapperobj, "Kill");
	}
	return Plugin_Handled;
}

stock int TF2_CreateGenericBomb(float vecOrigin[3], float flDamage = 0.0, float flRadius = 0.0,
		const char[] strParticle = "", const char[] strSound = "") {
	int iBomb = CreateEntityByName("tf_generic_bomb");
	DispatchKeyValueVector(iBomb, "origin", vecOrigin);
	DispatchKeyValueFloat(iBomb, "damage", flDamage);
	DispatchKeyValueFloat(iBomb, "radius", flRadius);
	DispatchKeyValue(iBomb, "health", "1");
	
	if (strlen(strParticle) > 0) {
		DispatchKeyValue(iBomb, "explode_particle", strParticle);
	}
	
	if (strlen(strSound) > 0) {
		DispatchKeyValue(iBomb, "sound", strSound);
	}
	
	char netclass[32];
	GetEntityNetClass(iBomb, netclass, sizeof(netclass));
	DebugToServer("bomb entity %s", netclass);
	
	DispatchSpawn(iBomb);
	return iBomb;
}

void DebugToServer(const char[] fmt, any ...) {
	if (g_bSpewGarbage) {
		char buffer[256];
		VFormat(buffer, sizeof(buffer), fmt, 2);
		LogServer("%s", buffer);
	}
}
