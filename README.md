# SM-TFCustomWeaponAttributes
A collection of attributes for the TF2 Custom Weapons plugin.

I don't run a Custom Weapons server myself (they were commissioned), so consider these unmaintained and provided without warranty (and for educational purposes).  If you'd like to tweak them yourself and submit pull requests back upstream, that'd be awesome!

The plugins are tested against Custom Weapons 2 (beta 6); no guarantees they will work in any future (or past) versions.

## List of attributes:

* `no secondary ammo from dispensers while active`:  Prevents a player with the attribute from acquiring ammo for their secondary weapon.  Uses gamedata with the DHooks extension to detect when the `CObjectDispenser::DispenseAmmo` function is called (so it does not prevent other ammo pickups while being healed by a dispenser), along with touch hooks on ammo packs.
* `exploding sapper`:  A sapper that explodes, with various configurable attributes.  Demonstrates the `player_sapped_object` event and using `tf_generic_bomb` to blow things up with kill credit for a specific player.
* `fires stunballs`:  Replaces the projectile fired from this weapon with Sandman balls.  Demonstrates a lot of reinventing the wheel.
* `per head attack increase`:  Attack speed increases per kill made with weapon.  Originally meant for swords.  Demonstrates an entity think hook to detect weapon use.
* `on kill blast and sentry resist`:  Applies resistances on kill.  Demonstrates overlay?
* `scout bonk override`:  A collection of attributes to implement [Saxton Spinach](https://www.youtube.com/watch?v=f2uOhzM7r-U).
