# SM-TFCustomWeaponAttributes
A collection of attributes for the TF2 Custom Weapons plugin.

I don't run a Custom Weapons server myself (they were commissioned), so consider these unmaintained and provided without warranty (and for educational purposes).

## List of attributes:

* `no secondary ammo from dispensers while active`:  Prevents a player with the attribute from acquiring ammo for their secondary weapon.  Uses gamedata with the DHooks extension to detect when the `CObjectDispenser::DispenseAmmo` function is called (so it does not prevent other ammo pickups while being healed by a dispenser), along with touch hooks on ammo packs.
* `exploding sapper`:  A sapper that explodes.  Demonstrates the `player_sapped_object` event and using `tf_generic_bomb` to blow things up with kill credit for a specific player.
