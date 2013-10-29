
// Serial LED controller 
// Software to drive your LED srop via a simple serial interface 
// Version 0.5   29 Oct 2013    Initual Public release 
// Uses The Adafruit NeoPixel library. https://github.com/adafruit/Adafruit_NeoPixel
// Some code and ideas was also sourced from https://github.com/reprappro/Marlin/tree/multimaterials/Slave 
// This software is free. Use as you wish. 
// My hope is people will add aditional feature to this product   

/*         Commands and syntax            
           -------------------

All parameters are assumed to fixed width, so prefix anything less than normal length with 0
eg input of 1 as a RGB value becomes 001


Command:     :0 Turn off all LED and disbale flash
Parameters:  no prameters

Command:     :1 Set a LED's COLOUR
Parameters:  LED number ## {-End LED number ##}, RGB value in RRR GGG BBB
Eg.          :1 00 255 000 000 ;Set LED 00 to RGB 255 000 000 (red full on)
Eg.          :1 00-59 000 000 2555 ; Set LED's 00 threw 59 to RGB 000 000 255 (blue full on)

Command:     :2 Get a LED's RGB colour
Parameters:  LED number ## {-End LED number ##}
Returns:     String of RGB values for each LED, all RGB values are 3 characters
Eg.          :2 00 ; Get LED 00 RGB values.
Eg.          :2 00-10 ; Get LED's 00 threw 10 RGB values

Command:     :3 Set a LED's blinking between two values
Parameters:  LED number ## {-End LED number ##}, start RGB value, end RGB value in RRR GGG BBB
Eg.          :3 00 255 000 000 000 255 000 ; Set LED 00 blinking from full red to full green
Eg.          :3 01 000 255 000 255 000 000 ; Set LED 01 blinking from full green to full red. This will be oposite timeing from the previous example.
Eg.          :3 00-59 000 000 255 000 000 000 ; Set LED's 00 threw 59 blinking from blue full on to all off

Command:     :4 Turn off blinking
Parameters:  LED number ## {-End LED number ##}
Eg.          :4 05 ; Stop LED 05 blinking
Eg.          :4 03-26 ; Stop Led's 03 threw 26 blinking

Command:     :5 Shift LED's left (where left is 0 and right is your heightest LED number). Any LED's pushed past 0 are lost, new leds are off.
Parameters:  number of LEDS ##
Eg.          :5 03 ; move all LED's left 3 places

Command:     :6 Shift LED's Right (where left is 0 and right is your heightest LED number). Any LED's pushed past NUMLEDS are lost, new leds are off.
Parameters:  number of LEDS ##
Eg.          :6 07 ; move all LED's right 7 places

Command:     :7 Roll LED's Left (where left is 0 and right is your heightest LED number). Any LED's pushed off on end roll onto the other end.
Parameters:  number of LEDS ##
Eg.          :7 02 ; Roll all LED's left 2 places

Command:     :8 Roll LED's Right (where left is 0 and right is your heightest LED number). Any LED's pushed off on end roll onto the other end.
Parameters:  number of LEDS ##
Eg.          :8 04 ; Roll all LED's right 4 places

*/

// User editable values 

#define LED_STRIP_PIN 18
#define NUMLEDS 60
#define DEBUG_IO Serial
#define MASTER_IO Serial //Serial1 Serial2 or Serial3 are also options, if you have them. 
#define DEBUG_BAUD 57600
#define MASTER_BAUD 57600

#include <Adafruit_NeoPixel.h>

// Parameter 1 = number of pixels in strip
// Parameter 2 = pin number (most are valid)
// Parameter 3 = pixel type flags, add together as needed:
//   NEO_RGB     Pixels are wired for RGB bitstream
//   NEO_GRB     Pixels are wired for GRB bitstream
//   NEO_KHZ400  400 KHz bitstream (e.g. FLORA pixels)
//   NEO_KHZ800  800 KHz bitstream (e.g. High Density LED strip)
Adafruit_NeoPixel strip = Adafruit_NeoPixel(NUMLEDS, LED_STRIP_PIN, NEO_GRB + NEO_KHZ800);

//Probbbaly shouldnt change anything beyond this point. Unless you know what your doing.  

#define BUFLEN 128 // input string
#define BEGIN_C ':'
#define END_C '\n'

char buf[BUFLEN];
uint8_t attr[NUMLEDS];
uint32_t colourstore[2][NUMLEDS];
int bp;  //buffer pointer 
boolean debug;
boolean inMessage;
int timer1_counter;
uint8_t iphase;

inline void debugMessage(char* s1)
{
  if(!debug)
   return;
  DEBUG_IO.println(s1);
}

inline void debugMessage(char* s1, char* s2)
{
  if(!debug)
   return;
  DEBUG_IO.print(s1);
  DEBUG_IO.println(s2);
}

String colourToString(uint32_t c) {
  unsigned char triet[3]  = {0,0,0};
  String s[3]; 
  
  for (int i=0; i<3; i++)   {
    triet[i] = ( c >> (i*8) ) & 0xFF;
    //DEBUG_IO.print(String(triet[i],HEX));
    s[i]=String(triet[i],DEC);
    while (s[i].length() < 3) {
      //DEBUG_IO.print(s[i]+" ");
      s[i] = "0"+s[i];
    }  
  }
  return String(s[2])+" "+String(s[1])+" "+String(s[0]);
} 

void incomming() {
  if (!MASTER_IO.available())
    return;

  char c = (char)MASTER_IO.read();
    switch(c)
    {
    case BEGIN_C:
       bp = 0;
       buf[0] = 0;
       inMessage = true;
       break;
       
    case END_C:
       if(inMessage)
       {
         buf[bp] = 0;
         bp = 0;
         inMessage = false;
         command();
         return;
       }
       break;
        
    default:
       if(inMessage)
       {
         buf[bp] = c;
         bp++;
       }
    }
       
    if(bp >= BUFLEN)
    {
      bp = BUFLEN-1;
      buf[bp] = 0;
      MASTER_IO.println("command buffer overflow");
    }
}

void setup() {
  debug = false;
  MASTER_IO.begin(MASTER_BAUD);
  //MASTER_IO.print("Online");
  if(debug) { 
    #if (defined(MASTER_IO) == defined(DEBUG_IO))
        DEBUG_IO.begin(DEBUG_BAUD);
    #endif
  }

  strip.begin();
  strip.show(); // Initialize all pixels to 'off'

  // initialize timer1 
  noInterrupts();           // disable all interrupts
  TCCR1A = 0;
  TCCR1B = 0;

  // Set timer1_counter to the correct value for our interrupt interval
  //timer1_counter = 64886;   // preload timer 65536-16MHz/256/100Hz
  //timer1_counter = 64286;   // preload timer 65536-16MHz/256/50Hz
  timer1_counter = 34286;   // preload timer 65536-16MHz/256/2Hz
  
  TCNT1 = timer1_counter;   // preload timer
  TCCR1B |= (1 << CS12);    // 256 prescaler 
  TIMSK1 |= (1 << TOIE1);   // enable timer overflow interrupt
  interrupts();             // enable all interrupts

}

ISR(TIMER1_OVF_vect)        // interrupt service routine 
{
  TCNT1 = timer1_counter;   // preload timer
  iphase ^= 1 << 0;
  do_blink(); 
  
}

void loop() {
  incomming();
}

void command() {
  if(!buf[0])
    return;
    
  debugMessage("Received: ", buf);    
    
  switch(buf[0]) {
    case '\n':
      break;

    case '0':
      debugMessage(":0");
      off(); 
      break;

    case '1':    //led (decimal) ## RRR GGG BBB
      debugMessage(":set rgbled");
      if (buf[4] == '-') {
        debugMessage(":- found");
        buf[4] = ' ';
        set_rgbled(atof(&buf[2]), atof(&buf[5]), atof(&buf[8]), atof(&buf[12]), atof(&buf[16]) );
      }
      else {
        set_rgbled(atof(&buf[2]),atof(&buf[5]),atof(&buf[9]),atof(&buf[13]));
      }
      break;

    case '2':    //get led :2 ##
      debugMessage(":get rgbled");
      if (buf[4] == '-') {
        debugMessage(":- found");
        buf[4] = ' ';
        get_rgbled(atof(&buf[2]), atof(&buf[5]));
      }
      else {
        get_rgbled(atof(&buf[2]));
      }
      break;

    case '3':    //set blink :3 ## RRR GGG BBB RRR GGG BBB
                 //       or :3 ##-## RRR GGG BBB RRR GGG BBB
      debugMessage(":set blink");
      if (buf[4] == '-') {
        debugMessage(":- found");
        buf[4] = ' ';
        set_blink(atof(&buf[2]), atof(&buf[5]), atof(&buf[8]), atof(&buf[12]), atof(&buf[16]), atof(&buf[20]), atof(&buf[24]), atof(&buf[28]) );
      }  
      else {
        set_blink(atof(&buf[2]), atof(&buf[5]), atof(&buf[9]), atof(&buf[13]), atof(&buf[17]), atof(&buf[21]), atof(&buf[25]) );
      }
      break;
      
    case '4':    //clear blink  
      debugMessage(":clear blink");
      if (buf[4] == '-') {
        debugMessage(":- found");
        buf[4] = ' ';
        clear_blink(atof(&buf[2]), atof(&buf[5]) );
      }  
      else {
        clear_blink(atof(&buf[2]));
      }
      break;

    case '5':    //shift left
        debugMessage(":shift left");
        shiftleft(atof(&buf[2]));
      break;
      
    case '6':    //shift right
        debugMessage(":shift right");
        shiftright(atof(&buf[2]));
      break;

    case '7':    //roll left
        debugMessage(":shift left");
        rollleft(atof(&buf[2]));
      break;
      
    case '8':    //roll right
        debugMessage(":shift right");
        rollright(atof(&buf[2]));
      break;
      
    default:
      MASTER_IO.print("Invalid command");
      break;
  }
}


//off

void off() {
  uint16_t i;
  for(i=0; i< strip.numPixels(); i++) {
    strip.setPixelColor(i, strip.Color(0,0,0));
    attr[i]=0;
  }
  strip.show();
}

//set_rgbled
void set_rgbled(uint8_t i,uint8_t r,uint8_t g,uint8_t b) {
  strip.setPixelColor(i, strip.Color(r,g,b)); 
  strip.show(); 
}
void set_rgbled(uint8_t i, uint8_t j, uint8_t r, uint8_t g, uint8_t b) {
  for (uint8_t k=i; k < j+1 ; k++) 
  {
    strip.setPixelColor(k, strip.Color(r,g,b)); 
  }
}

//get_rgbled
void get_rgbled(uint8_t i) {
  MASTER_IO.print(colourToString(strip.getPixelColor(i)));
  MASTER_IO.print(END_C);
}
void get_rgbled(uint8_t i, uint8_t j) {
  for (uint8_t k=i; k < j+1 ; k++) 
  {
    MASTER_IO.print(colourToString(strip.getPixelColor(k))); 
    if (k != j) {
      MASTER_IO.print(" ");
    }
    else {
      MASTER_IO.print(END_C);  
    }
  }
}

//set_blink 
void set_blink(uint8_t i, uint8_t r1,uint8_t g1,uint8_t b1, uint8_t r2,uint8_t g2,uint8_t b2) {
  attr[i]=1;
  colourstore[0][i]=strip.Color(r1,g1,b1);
  colourstore[1][i]=strip.Color(r2,g2,b2);
}
void set_blink(uint8_t i, uint8_t j, uint8_t r1, uint8_t g1, uint8_t b1, uint8_t r2,uint8_t g2,uint8_t b2) {
  for (uint8_t k=i; k < j+1 ; k++) 
  {
    attr[k]=1;
    colourstore[0][k]=strip.Color(r1,g1,b1);
    colourstore[1][k]=strip.Color(r2,g2,b2);
  }
}

//clear_blink 
void clear_blink(uint8_t i) {
  attr[i]=0;
}
void clear_blink(uint8_t i, uint8_t j) {
  for (uint8_t k=i; k < j+1 ; k++) {
    attr[k]=0;
  }
}

//do_blink
void do_blink() {
  uint8_t j;
  for(j=0; j < strip.numPixels();j++) 
  {
    if(attr[j] == 1) {
      //debugMessage(":blink found");
      strip.setPixelColor(j, colourstore[iphase][j] );
    }
  }
  strip.show();
}  

//shift left
void shiftleft(uint8_t i) {
  uint8_t j;
  for(j=i; j < strip.numPixels();j++) {
    strip.setPixelColor(j-i, strip.getPixelColor(j));
  }
  for(j=strip.numPixels()-i;j < strip.numPixels();j++) {
    strip.setPixelColor(j, strip.Color(0,0,0)); 
  }
  strip.show(); 
}

//shift right 
void shiftright(uint8_t i) {
  uint8_t j;
  for(j=0; j < strip.numPixels()-i+1;j++) {
    strip.setPixelColor(strip.numPixels()-j, strip.getPixelColor(strip.numPixels()-j-i));
  }
  for(j=0; j < i;j++) {
    strip.setPixelColor(j, strip.Color(0,0,0));
  }
  strip.show(); 
}

//roll left
void rollleft(uint8_t i) {
  uint8_t j;
  uint32_t tmp_colourstore[NUMLEDS];
  for(j=0; j < strip.numPixels();j++) {
    tmp_colourstore[j] = strip.getPixelColor(j);
  }
  for(j=i; j < strip.numPixels();j++) {
    strip.setPixelColor(j-i, tmp_colourstore[j]);
  }
  for(j=0;j < i;j++) {
    strip.setPixelColor(strip.numPixels()-1-j, tmp_colourstore[j]); 
  }
  strip.show(); 
}

//roll right
void rollright(uint8_t i) {
  uint8_t j;
  uint32_t tmp_colourstore[NUMLEDS];
  for(j=0; j < strip.numPixels();j++) {
    tmp_colourstore[j] = strip.getPixelColor(j);
  }
  for(j=0; j < strip.numPixels()-i+1;j++) {
    strip.setPixelColor(strip.numPixels()-j, strip.getPixelColor(strip.numPixels()-j-i));
  }
  for(j=0; j < i;j++) {
    strip.setPixelColor(j, tmp_colourstore[strip.numPixels()-1-j]);
  }
  strip.show(); 
}


