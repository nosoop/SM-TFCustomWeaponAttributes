#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools_functions>
#include <tf2_stocks>
#include <customweaponstf>

// See nosoop/stocksoup @ github for stocks.
#include <stocksoup/log_server>
#include <stocksoup/tf/glow_model>
#include <stocksoup/entity_tools>

#pragma newdecls required

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
    name = "[TF2] Custom Weapon Attribute:  Cursed Gibs",
    author = "nosoop",
    description = "Killed players drop gibs from attacker or assister",
    version = PLUGIN_VERSION,
    url = "https://github.com/nosoop/SM-TFCustomWeaponAttributes/"
}

#define CW2_PLUGIN_NAME "custom-weapon-soup"
#define ATTR_CURSED_GIBS "cursed gibs on kill credit"
#define ATTR_NO_PLAYER_AMMO_PICKUPS "no player ammo pickups"

#define FSOLID_TRIGGER 0x08

ArrayList g_CursedGibWeapons;
ArrayList g_NoPlayerAmmoPickups;

char g_classNames[][] = {
	"", "scout", "sniper", "soldier", "demo", "medic", "heavy", "pyro", "spy", "engineer"
};

int g_classGibs[] = {
	0, 9, 7, 8, 6, 8, 7, 8, 7, 7
};

public void OnPluginStart() {
	HookEvent("player_death", OnPlayerDeath);
	
	g_CursedGibWeapons = new ArrayList();
	g_NoPlayerAmmoPickups = new ArrayList();
}

public void OnMapStart() {
	for (int i = 0; i < sizeof(g_classGibs); i++) {
		char gibModel[PLATFORM_MAX_PATH];
		
		for (int g = 0; g < g_classGibs[i]; g++) {
			Format(gibModel, sizeof(gibModel), "models/player/gibs/%sgib%03d.mdl",
					g_classNames[i], g + 1);
			
			PrecacheModel(gibModel);
		}
	}
	
	// tf_ammo_packs are the ammo items dropped by players
	int ammo = -1;
	while ( (ammo = FindEntityByClassname(ammo, "tf_ammo_pack")) != -1 ) {
		HookAmmoTouch(ammo);
	}
}

// standard stuff
public Action CustomWeaponsTF_OnAddAttribute(int weapon, int client, const char[] attrib,
		const char[] plugin, const char[] value) {
	if (StrEqual(plugin, CW2_PLUGIN_NAME, false)) {
		if (StrEqual(attrib, ATTR_CURSED_GIBS)) {
			g_CursedGibWeapons.Push(weapon);
			return Plugin_Handled;
		} else if (StrEqual(attrib, ATTR_NO_PLAYER_AMMO_PICKUPS)) {
			g_NoPlayerAmmoPickups.Push(weapon);
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public void OnEntityDestroyed(int entity) {
	int index;
	if ((index = g_CursedGibWeapons.FindValue(entity)) != -1) {
		g_CursedGibWeapons.Erase(index);
	} else if ((index = g_NoPlayerAmmoPickups.FindValue(entity)) != -1) {
		g_NoPlayerAmmoPickups.Erase(index);
	}
}

public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int assister = GetClientOfUserId(event.GetInt("assister"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	
	if (victim && PlayerHasCursedGibs(attacker) || PlayerHasCursedGibs(assister)) {
		SpawnCursedGibs(victim);
	}
}

bool PlayerHasCursedGibs(int client) {
	if (client && client <= MaxClients) {
		for (int i = 0; i <= TFWeaponSlot_Melee; i++) {
			int hWeapon = GetPlayerWeaponSlot(client, i);
			
			if (g_CursedGibWeapons.FindValue(hWeapon) != -1) {
				return true;
			}
		}
	}
	return false;
}

// adapted from the bread plugin https://forums.alliedmods.net/showthread.php?p=2150119 
void SpawnCursedGibs(int client) {
	int classIndex = view_as<int>(TF2_GetPlayerClass(client));
	
	if (classIndex == 0) {
		return;
	}
	
	for (int i = 0; i < 5; i++) {
		int hCursedGib = CreateEntityByName("item_bonuspack");
		
		if (IsValidEntity(hCursedGib)) {
			float vecVelocity[3], vecPos[3];
			GetClientAbsOrigin(client, vecPos);
			
			vecVelocity[0] = GetRandomFloat(-400.0, 400.0);
			vecVelocity[1] = GetRandomFloat(-400.0, 400.0);
			vecVelocity[2] = GetRandomFloat(300.0, 500.0);
			
			vecPos[0] += GetRandomFloat(-5.0, 5.0);
			vecPos[1] += GetRandomFloat(-5.0, 5.0);
			
			// get random gib model
			// we could try to improve by not spawning two of the same model but who would notice
			char gibModel[PLATFORM_MAX_PATH];
			Format(gibModel, sizeof(gibModel), "models/player/gibs/%sgib%03d.mdl",
					g_classNames[classIndex], GetRandomInt(1, g_classGibs[classIndex]));
			
			// SetEntityModel(hCursedGib, gibModel);
			DispatchKeyValue(hCursedGib, "powerup_model", gibModel);
			DispatchSpawn(hCursedGib);
			
			SetEntityMoveType(hCursedGib, MOVETYPE_FLYGRAVITY);
			
			SetEntProp(hCursedGib, Prop_Send, "m_bSimulatedEveryTick", true);
			SetEntProp(hCursedGib, Prop_Send, "m_nSolidType", 2);
			SetEntProp(hCursedGib, Prop_Send, "movecollide", true);
			
			SetEntityGravity(hCursedGib, 5.0);
			
			TeleportEntity(hCursedGib, vecPos, NULL_VECTOR, vecVelocity);
			
			
			// TODO figure out proper collisions that play nicely with starttouch
			// apparently there's no way to do this
			//SetEntProp(hCursedGib, Prop_Data, "m_CollisionGroup", 4); // COLLISION_GROUP_PLAYER
			//SetEntProp(hCursedGib, Prop_Send, "m_usSolidFlags", 0x0004 | 0x0008); // FSOLID_NOT_SOLID | FSOLID_TRIGGER from const.h
			//SetEntProp(hCursedGib, Prop_Data, "m_nSolidType", 2); // SOLID_VPHYSICS
			//SetEntProp(hCursedGib, Prop_Data, "m_spawnflags", 1024); // 
			
			
			AddGlowModel(hCursedGib);
			
			CreateTimer(10.0, OnCursedGibDespawn, EntIndexToEntRef(hCursedGib),
					TIMER_FLAG_NO_MAPCHANGE);
			
			// TODO figure out proper parenting setup -- the bones aren't correctly offset
			int hParticle = CreateParticle("superrare_greenenergy");
			if (IsValidEntity(hParticle)) {
				TeleportEntity(hParticle, vecPos, NULL_VECTOR, NULL_VECTOR);
				ParentEntity(hCursedGib, hParticle);
			}
			
			SDKHook(hCursedGib, SDKHook_StartTouch, OnCursedGibTouch);
			
			RequestFrame(Frame_RemoveRagdoll, GetClientUserId(client));
		}
	}
}

public void Frame_RemoveRagdoll(int userid) {
	int client = GetClientOfUserId(userid);
	
	if (client) {
		int hRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if (IsValidEntity(hRagdoll)) {
			AcceptEntityInput(hRagdoll, "Kill");
		}
	}
}

public Action OnCursedGibDespawn(Handle timer, int gibReference) {
	int gib = EntRefToEntIndex(gibReference);
	
	if (gib != INVALID_ENT_REFERENCE) {
		AcceptEntityInput(gib, "Kill");
	}
	return Plugin_Handled;
}

public Action OnCursedGibTouch(int gib, int entity) {
	if (entity > 0 && entity <= MaxClients) {
		// touched by a player
		int nHealth = GetClientHealth(entity);
		int nMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send,
				"m_iMaxHealth", _, entity);
		
		int nHealAmount = GetRandomInt(5, 15);
		
		// cap possible overheal
		if (nHealAmount > nMaxHealth - nHealth) {
			nHealAmount = nMaxHealth - nHealth;
		}
		
		if (nHealAmount > 0) {
			SetEntityHealth(entity, nHealth + nHealAmount);
			
			// player health HUD notification
			Event event = CreateEvent("player_healonhit");
			if (event) {
				event.SetInt("amount", nHealAmount);
				event.SetInt("entindex", entity);
				
				event.Fire();
			}
			
			AcceptEntityInput(gib, "Kill");
		}
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

int CreateParticle(const char[] effectName) {
	int particle = CreateEntityByName("info_particle_system");
	
	if (IsValidEdict(particle)) {
		DispatchKeyValue(particle, "effect_name", effectName);
		DispatchSpawn(particle);
		
		ActivateEntity(particle);
		AcceptEntityInput(particle, "start");
	}
	return particle;
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrContains(classname, "tf_ammo_pack", false) == 0) {
		HookAmmoTouch(entity);
	}
}

void HookAmmoTouch(int ammo) {
	// LogServer("%d hooked for ammo", ammo);
	SDKHook(ammo, SDKHook_StartTouch, OnAmmoTouched);
	SDKHook(ammo, SDKHook_Touch, OnAmmoTouched);
}

bool PlayerDeniedAmmoDrops(int client) {
	if (client && client <= MaxClients) {
		for (int i = 0; i <= TFWeaponSlot_Melee; i++) {
			int hWeapon = GetPlayerWeaponSlot(client, i);
			
			if (g_NoPlayerAmmoPickups.FindValue(hWeapon) != -1) {
				return true;
			}
		}
	}
	return false;
}

public Action OnAmmoTouched(int ammopack, int entity) {
	if (entity > 0 && entity <= MaxClients && PlayerDeniedAmmoDrops(entity)) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}