# TF2 Custom Weapon Attributes Collection
A collection of previously commissioned attributes ported to the
[TF2 Custom Attributes framework], which is my replacement for the various Custom Weapons
projects.

[TF2 Custom Attributes framework]: https://github.com/nosoop/SM-TFCustAttr

![XKCD image on standards](https://imgs.xkcd.com/comics/standards.png)

I've learned a bunch since I've written these originally, though while I am doing a port, I may
or may not put in effort in rewriting the ~~dark magic~~ hackjobs that were initially
implemented.

## Ported attributes

* `is tossable teleporter`:  Now works with non-milk projectiles.  Modified the plugin to use
various functions from `stocksoup`, making the particle effects tempents, etc.
* `minicrits on bleed`:  Modified to use
[my crit-supported OnTakeDamage forwards][TF-OnTakeDamage].
* `per head attack increase`:  Now uses the decapitation head counter and overwrites the game's
functions on setting speed / health modifiers on the sword with DHooks.
* `damage to heals`:  Straight port and used external copy of `TF2_HealPlayer`.  Now capable of
specifying damage multiplier returned as heals.

[TF-OnTakeDamage]: https://github.com/nosoop/SM-TFOnTakeDamage