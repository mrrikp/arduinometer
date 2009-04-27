#include "Ethernet2.h"
#include "WString.h"
#include "stdio.h"

// --- [ Pin setup ] ---
int sensorPin = 5;
int ledPin = 9;
int fanPin = 7;
int tempPin = 3;
int unlockPin = 8;

// --- [ Ethernet setup ] ---
static uint8_t mac[6] = { 0x02, 0xAA, 0xAA, 0xCC, 0x00, 0x22 };
static uint8_t ip[4] = { 192, 168, 1, 99 };
static uint8_t gateway[4] = { 192, 168, 1, 2 };
String url = String(25);
int maxLength=25;

// --- [ Variables to control when the unit fan kicks in/cuts out... ] ---
float maxTemp = 26.0;
float minTemp = 24.0;

// --- [ Variables to store our sensor values ] ---
volatile int totalTicks = 0;
float tempc = 0.0;
int maxi = -100, mini = 100;

// --- [ Misc. vars ] ---
float inputVolts = 5.01;
int previousState = -2;
int delayMs = 1500;
int i;
boolean lock;

Server server(80);

void setup() {     
  pinMode(ledPin, OUTPUT);
  pinMode(fanPin, OUTPUT);  
  pinMode(sensorPin, INPUT);
  pinMode(unlockPin, INPUT);
  previousState = digitalRead(sensorPin);      
  Serial.begin(115200);                                   // Use serial for debugging locally...
  Serial.println("Ardugas server saying: Howdy!");  
  Ethernet.begin(mac, ip, gateway);
  server.begin();    
}

void loop() {  
  checkUnitTemp();                                      // Take action based on unit temp
  checkSensor();                                        // Check the gas meter sensor
  getCurrentTemperature();                              // Get the unit temperature  
  listenWeb();                                          // Handle any web connections  
  digitalWrite(ledPin, !digitalRead(sensorPin));        // Light LED if sensor is LOW
}

// Serve pachube EEML and accept a querystring param to set the current value
void listenWeb() {   
 
 boolean read_url = true;
 boolean unlock = false;

 Client client = server.available();
  if (client) {
    
    Serial.println("Ethernet client connected...");
    
    // an http request ends with a blank line
    boolean current_line_is_blank = true;
    int valuesChanged = 0;
    while (client.connected()) {
      
      if (client.available()) {
                        
        char c = client.read();        
          if (url.length() < maxLength) {          
            url.append(c);
          }                      
        if (c == '\n' && current_line_is_blank) {
                    
           // send a standard http response header, but change the response type to text/xml
          client.println("HTTP/1.1 200 OK");
          client.println("Content-Type: text/xml");
          client.println();
          
          // This is our unlock pin. When set to high, we allow the querystring parameter 'x' to force-set our meter value.
          if (digitalRead(unlockPin) == HIGH) {
            unlock = true;
          }
          
          if (url.contains("x") && unlock) {
            Serial.println(url);
            String v = String(10);            
            int startIndex = url.indexOf('=')+1;
            int stopIndex = url.indexOf('H');
            v = url.substring(startIndex, stopIndex); 
            Serial.println(v);
            totalTicks = atoi(v);   
          } 
                                    
          int t = tempc;
          
          // EEML
          client.println("<eeml xmlns='http://www.eeml.org/xsd/005' xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance' xsi:schemaLocation='http://www.eeml.org/xsd/005 http://www.eeml.org/xsd/005/005.xsd'>");
          client.println("<environment>");
          
          client.println("<location exposure='indoor' domain='physical' disposition='fixed'>");
          client.println("<name>Ardugas Server</name>");
          client.println("</location>");
          
          // Gas Meter Reading
          client.println("<data id='0'>");
          client.println("<tag>gas</tag><tag>cubic metres</tag>");
          client.print("<value>");
          client.print(totalTicks);
          client.println("</value>");
          client.println("</data>");
          
          client.println("<data id='1'>");
          client.println("<tag>temperature</tag><tag>degrees</tag><tag>celsius</tag>");
          client.print("<value>");
          client.print(t);
          client.print("</value>");          
          client.println("</data>");         
          
          client.println("</environment>");
          client.println("</eeml>");
                 
          client.println(); 
 
          break;
          
        }
        
        if (c == '\n') {
          // we're starting a new line
          current_line_is_blank = true;
        } else if (c != '\r') {
          // we've gotten a character on the current line
          current_line_is_blank = false;
        }
        
      }
    }
    // give the web browser time to receive the data
    url = "";            
    delay(5);
    client.stop();
  } 
  
}

// Switch the cooling fan on if it's too hot!
void checkUnitTemp() {
 if (tempc >= maxTemp) {
   digitalWrite(fanPin, HIGH);
 } 
 if (tempc <= minTemp) {
   digitalWrite(fanPin, LOW);
 }
}

// Retrieve the current temperature
void getCurrentTemperature() {  
  tempc = inputVolts * ((analogRead(tempPin) * 100.0) / 1024.0);
  if(tempc > maxi) {maxi = tempc;} // record max temperature
  if(tempc < mini) {mini = tempc;} // record min temperature     
}

// Count sensor values
void checkSensor() { 
  int currentState = digitalRead(sensorPin);
  if (currentState == LOW && previousState == HIGH) {
    if (!lock) {
      lock = true;
      delay(delayMs);
      totalTicks++;
    }
  }  
  if (currentState == HIGH && previousState == LOW) {
    lock = false;
  }  
  previousState = currentState;  
}
