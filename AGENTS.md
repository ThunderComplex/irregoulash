# TopDown Shooter  

## Game overview  

This game is a topdown 2D shooter. The player moves using WASD, and looks around using the mouse.  
Movement is always screen based, not mouse based, W always moves up, not forward in the direction of the mouse.  
The player will have the ability to pick up different weapons, switch between them on the fly, and even upgrade them.  
In addition, the player will have ARPG-style abilities and consumables.  
The player's vision is line of sight based. Players can't see behind them or around corners.  

## Level authoring  

Authoring levels must be simple. Making a new level and integrating it into the game should be as easy as possible.  
It should not be possible to break new levels by forgetting to add game-important nodes (like a audio manager for example) 
to the level.  
There are no procedurally generated levels. However, procgen may be used to aide in creating levels.  
Every level should have at least one exit that leads to another level. Reaching the final exit means you won the game.  

## Enemy AI  

Enemy AI should be basic but also line of sight based. You should be able to sneak up on unaware enemies.  
Enemies either patrol or head to the last location they saw the player.
