Japanese Walking Apple Watch App

Help me write a spec for building an apple watch app. 

Requirements
* A simple app to support the Japanese Walking Method, which is 4 mins of fast walking and 4 mins of recovery walking. 
* After starting the app, there should be one "Start" button. 
* if i click anywhere except "stop" finish current stage and move to next
* When Start is clicked on the watch
    * Repeat forever:
        * 4 min timer starts.
        * The watch vibrates, plays chime up, speaks “Fast walk”
        * The watch displays “Fast walk” and a countdown timer per the screen shot attached.
        * When the timer reaches 00:00,
        * The watch vibrates, plays chime down, then speaks “Slow walk”
        * A new 4 min countdown timer starts
        * The display changes to the “Slow walk” and 4 min count timer per attached screen shot