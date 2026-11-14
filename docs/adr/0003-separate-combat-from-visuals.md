# Separate combat rules from replaceable actor and sword visuals

Swordster's existing presentation is proof-of-concept, and later sprite adoption
should require minimal changes. Give actors and swords replaceable visual child
scenes, with combat scripts owning logical pose, collision geometry, action phases
and damage timing. Visuals consume that state and combat cues; animation callbacks
and texture dimensions must not control gameplay. This costs a small explicit
presentation boundary now, but avoids coupling the port to procedural drawing or
a particular sprite pack and permits later art replacement without rewriting combat.
