/**
 * Custom Weapons Attribute: No secondary ammo from dispensers while active
 * Requested by Karma Charger
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>
#include <dhooks>

#include <tf2_stocks>
#include <customweaponstf>

#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
    name = "[TF2] Custom Weapons Attribute: No Secondary Ammo From Dispensers While Active",
    author = "nosoop",
    description = "Prevents players from getting ammo for their secondary weapon while the current weapon is active.",
    version = PLUGIN_VERSION,
    url = "https://github.com/nosoop/SM-TFCustomWeaponAttributes"
}

#define CW2_PLUGIN_NAME "custom-weapon-soup"
#define ATTR_NO_SEC_AMMO_FROM_DISPENSERS_WHILE_ACTIVE "no secondary ammo from dispensers while active"

ArrayList g_NoSecondaryAmmoEntities;

Handle g_hDispenseAmmo;

// prevent ammo pickup while dispenser is providing ammo
bool g_bDisableAmmoPickup[MAXPLAYERS+1];

public Action CustomWeaponsTF_OnAddAttribute(int weapon, int client, const char[] attrib, const char[] plugin, const char[] value) {
	// Attach attribute if desired
	if (StrEqual(plugin, CW2_PLUGIN_NAME, false) && StrEqual(attrib, ATTR_NO_SEC_AMMO_FROM_DISPENSERS_WHILE_ACTIVE)) {
		g_NoSecondaryAmmoEntities.Push(weapon);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}


public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cw2_no_secondary_from_dispenser");
	
	if (hGameConf == null) {
		SetFailState("Missing gamedata");
	}
	
	int offsetDispenseAmmo = GameConfGetOffset(hGameConf, "CObjectDispenser::DispenseAmmo");
	g_hDispenseAmmo = DHookCreate(offsetDispenseAmmo, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity, CObjectDispenser_DispenseAmmo);
	DHookAddParam(g_hDispenseAmmo, HookParamType_CBaseEntity, _, DHookPass_ByRef);
	delete hGameConf;
	
	g_NoSecondaryAmmoEntities = new ArrayList();
		
	HookExistingEntities();
	AddNormalSoundHook(SoundHook_DispenserAmmo);
}

public void OnClientPutInServer(int client) {
	g_bDisableAmmoPickup[client] = false;
}

/**
 * Handle late-loaded plugin -- hook the necessary entities
 */
void HookExistingEntities() {
	char AMMOPACK_CLASSNAMES[][] = {
		"item_ammopack_full",
		"item_ammopack_medium",
		"item_ammopack_small"
	};
	
	int entity = -1;
	
	for (int i = 0; i < sizeof(AMMOPACK_CLASSNAMES); i++) {
		while (( entity = FindEntityByClassname(entity, AMMOPACK_CLASSNAMES[i]) ) != -1) {
			HookAmmoPack(entity);
		}
	}
	
	entity = -1;
	while ( (entity = FindEntityByClassname(entity, "obj_dispenser")) != -1 ) {
		OnDispenserSpawnPost(entity);
	}
}

/**
 * Sound hook to prevent the dispenser ammo from 
 */
public Action SoundHook_DispenserAmmo(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH],
		int &entity, int &channel, float &volume, int &level, int &pitch, int &flags) {
	// BaseCombatCharacter.AmmoPickup
	
	// Used for dispensers and building fragment pickups
	if (StrEqual(sample, "items/ammo_pickup.wav")) {
		// Stop if it is emitted from a player that can't pick up secondary ammo
		// TODO how can we tell if they are near a dispenser?
		if (IsInGamePlayer(entity) && !CanGetSecondaryAmmoFromDispensers(entity)) {
			return Plugin_Stop;
		}
		
		// Dirty hack:
		// If dispenser, don't allow those that can't pick up secondary ammo to hear it
		char classname[32];
		GetEntityClassname(entity, classname, sizeof(classname));
		if (StrEqual(classname, "obj_dispenser", false)) {
			int nListeningClients;
			
			for (int i = 0; i < numClients; i++) {
				int client = clients[i];
				if (client == 0 || IsInGamePlayer(client) && CanGetSecondaryAmmoFromDispensers(client)) {
					clients[nListeningClients++] = client;
				}
			}
			
			numClients = nListeningClients;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "obj_dispenser", false)) {
		SDKHook(entity, SDKHook_SpawnPost, OnDispenserSpawnPost);
	} else if (StrContains(classname, "item_ammopack_") > -1) {
		HookAmmoPack(entity);
	}
}

public void OnDispenserSpawnPost(int dispenser) {
    DHookEntity(g_hDispenseAmmo, false, dispenser);
}

/**
 * Hooks the dispenser's "dispense ammo" functionality.
 * Stores the current ammo count and re-applies it on the next frame.
 */
public MRESReturn CObjectDispenser_DispenseAmmo(int pThis, Handle hReturn, Handle hParams) {
	int client = DHookGetParam(hParams, 1);
	
	if (!CanGetSecondaryAmmoFromDispensers(client)) {
		DataPack pack = new DataPack();
		pack.WriteCell(GetClientUserId(client));
		pack.WriteCell(GetAmmoForSlot(client, TFWeaponSlot_Secondary));
		
		pack.WriteCell(GetMetal(client));
		pack.WriteCell(GetAmmoForSlot(client, TFWeaponSlot_Primary));
		
		RequestFrame(RequestFrame_ResetSecondaryAmmo, pack);
		
		g_bDisableAmmoPickup[client] = true;
	}
	
	return MRES_Ignored;
}

/**
 * Reset ammo count.
 */
public void RequestFrame_ResetSecondaryAmmo(DataPack pack) {
	pack.Reset();
	
	int client = GetClientOfUserId(pack.ReadCell());
	int nSecondaryAmmo = pack.ReadCell();
	int nMetal = pack.ReadCell();
	int nPrimaryAmmo = pack.ReadCell();
	
	if (client > 0) {
		int hSecondaryWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
		
		// Reset ammo quantity to value from last frame
		// There's no other way to gain ammo for secondary besides ammo packs, right?
		SetAmmo(client, hSecondaryWeapon, nSecondaryAmmo);
		
		// Check if player received non-secondary ammo
		bool bReceivedMetal = nMetal != GetMetal(client);
		bool bReceivedPrimaryAmmo = nPrimaryAmmo != GetAmmoForSlot(client, TFWeaponSlot_Primary);
		if (bReceivedMetal || bReceivedPrimaryAmmo) {
			// okay, I can't seem to play the sound through emitgamesound because... ??????
			ClientCommand(client, "playgamesound BaseCombatCharacter.AmmoPickup");
			ClientCommand(client, "playgamesound BaseCombatCharacter.AmmoPickup");
		}
		
		g_bDisableAmmoPickup[client] = false;
	}
	delete pack;
}

public void OnEntityDestroyed(int entity) {
	// Remove from attribute list
	int listIndex = g_NoSecondaryAmmoEntities.FindValue(entity);
	if (listIndex > -1) {
		g_NoSecondaryAmmoEntities.Erase(listIndex);
	}
}

/* Ammo pack utility */

void HookAmmoPack(int ammopack) {
	SDKHook(ammopack, SDKHook_Touch, OnAmmoPackTouch);
}

/**
 * Prevents ammo packs from being touched for the one frame we save / retore secondary ammo count.
 */
public Action OnAmmoPackTouch(int ammopack, int player) {
	if (IsInGamePlayer(player) && g_bDisableAmmoPickup[player]) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

/* Attribute "no secondary ammo from dispensers while active" */

/**
 * Returns whether or not the given client does not have the
 * "no secondary ammo from dispensers while active"
 * attribute on their currently active weapon.
 */
bool CanGetSecondaryAmmoFromDispensers(int client) {
	int hActiveWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
	return (g_NoSecondaryAmmoEntities.FindValue(hActiveWeapon) < 0);
}

/* Utility stocks */

stock bool IsInGamePlayer(int client) {
	return (client > 0 && client <= MaxClients) && IsClientInGame(client);
}

// Stock from AdvancedInfiniteAmmo
stock void SetMetal(int client, int iMetal = 999) {
	SetEntProp(client, Prop_Data, "m_iAmmo", iMetal, 4, 3);
}

// Custom getter
stock int GetAmmoForSlot(int client, int slot) {
	int hWeapon = GetPlayerWeaponSlot(client, slot);
	return GetAmmo(client, hWeapon);
}

stock int GetAmmo(int client, int iWeapon) {
	int iAmmoType = GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType");
	if (iAmmoType != -1) {
		return GetEntProp(client, Prop_Data, "m_iAmmo", _, iAmmoType);
	}
	return -1;
}

// Custom getter
stock int GetMetal(int client) {
	return GetEntProp(client, Prop_Data, "m_iAmmo", 4, 3);
}

// Stock from AdvancedInfiniteAmmo
stock void SetAmmo(int client, int iWeapon, int iAmmo = 500) {
	int iAmmoType = GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType");
	if (iAmmoType != -1) {
		SetEntProp(client, Prop_Data, "m_iAmmo", iAmmo, _, iAmmoType);
	}
}
