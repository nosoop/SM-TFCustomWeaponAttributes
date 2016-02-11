/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <dhooks>

#pragma newdecls required

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
    name = "[TF2] Sapper MvM Cooldown Test",
    author = "Author!",
    description = "Try to see if we can force the sapper cooldown outside of MvM.",
    version = PLUGIN_VERSION,
    url = "localhost"
}

Handle g_DHookSapperCharge;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cw2_sapper_cooldown");
	if (hGameConf == null) {
		SetFailState("Missing gamedata");
	}
	
	int offsetSapperCanCharge = GameConfGetOffset(hGameConf, "CTFWeaponSapper::CanCharge");
	g_DHookSapperCharge = DHookCreate(offsetSapperCanCharge, HookType_Entity, ReturnType_Bool,
			ThisPointer_CBaseEntity, OnSapperCanCharge);
	
	delete hGameConf;
	
	int entity = -1;
	while ( (entity = FindEntityByClassname(entity, "tf_weapon_sapper")) > 0 ) {
		OnSapperCreated(entity);
	}
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "tf_weapon_sapper")) {
		OnSapperCreated(entity);
	}
}

void OnSapperCreated(int sapper) {
	DHookEntity(g_DHookSapperCharge, true, sapper);
	PrintToServer("hooked sapper");
}

public MRESReturn OnSapperCanCharge(int sapper, Handle hReturn) {
	PrintToServer("Sapper %d can charge? %b", sapper, DHookGetReturn(hReturn));
	return MRES_Ignored;
}
