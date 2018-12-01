// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include <math.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 16                  //image height
#define  IMWD 16                  //image width

typedef unsigned char uchar;      //using uchar as shorthand

port p_scl = XS1_PORT_1E;         //interface ports to orientation
port p_sda = XS1_PORT_1F;

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out)
{
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ ) {
      c_out <: line[ x ];
      printf( "-%4.1d ", line[ x ] ); //show image values
    }
    printf( "\n" );
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );
  return;
}

#define alive (uchar)255
#define ded (uchar)0
unsigned char checkAlive(int x, int y, unsigned char grid[IMHT][IMWD])
{
    if (x >= 0 && x < IMWD && y >= 0 && y < IMHT)
    {
        return grid[x][y] == alive;
    }
    else
    {
        return 0;
    }
}
double timeInSeconds(uint32_t counter, uint32_t timerValue, uint32_t interval)
{
    return (counter * ((double)interval / (double)100000000)) + timerValue / (double)100000000;
}
/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend c_out, chanend fromAcc, chanend c_timer)
{

  uchar val;
  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
  printf( "Waiting for Board Tilt...\n" );
  fromAcc :> int value;

  //Read in and do something with your image values..
  //This just inverts every pixel, but you should
  //change the image according to the "Game of Life"
  unsigned char grid[IMHT][IMWD];
  printf( "Reading image...\n" );
  for( int y = 0; y < IMHT; y++ ) {   //go through all lines
    for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
      c_in :> val;                    //read the pixel value
      grid[x][y] = val;
    }
  }

  uint32_t startCounter, startTimer;
  c_timer <: 3;
  c_timer :> startCounter;
  c_timer :> startTimer;

  int maxrounds = 10;
  for (int rounds = 0; rounds < maxrounds; rounds++)
  {
      //find which cells live or die
      unsigned char newgrid[IMHT][IMWD];
      for (int x = 0; x < IMWD; x++)
      {
          for (int y = 0; y < IMHT; y++)
          {
              unsigned char neighbors = 0;
              neighbors += checkAlive(x + 1, y, grid);
              neighbors += checkAlive(x + 1, y + 1, grid);
              neighbors += checkAlive(x + 1, y - 1, grid);
              neighbors += checkAlive(x - 1, y, grid);
              neighbors += checkAlive(x - 1, y + 1, grid);
              neighbors += checkAlive(x - 1, y - 1, grid);
              neighbors += checkAlive(x, y + 1, grid);
              neighbors += checkAlive(x, y - 1, grid);
              if (grid[x][y] == alive)
              {
                  if (neighbors > 3 || neighbors < 2)
                  {
                      newgrid[x][y] = ded;
                  }
                  else
                  {
                      newgrid[x][y] = alive;
                  }
              }
              else if (neighbors == 3)
              {
                  newgrid[x][y] = alive;
              }
              else
              {
                  //printf("Carrying over value %u", (uchar)grid[x][y]);
                  newgrid[x][y] = ded;
              }
          }
      }
//      printf("--------------------------------------------------\n");
//      for (int x = 0; x < IMWD; x++)
//      {
//          for (int y = 0; y < IMHT; y++)
//          {
//              if ((uchar)newgrid[x][y] == alive)
//              {
//                  printf(" X ");
//              }
//              else if ((uchar)newgrid[x][y] == ded)
//              {
//                  printf(" - ");
//              }
//              else
//              {
//                  printf("%u", (uchar)newgrid[x][y]);
//              }
//              grid[x][y] = newgrid[x][y];
//          }
//          printf("\n");
//      }
//      printf("--------------------------------------------------\n");
//      //c_out <: (uchar)( val ^ 0xFF ); //send some modified pixel out
//      printf( "\nOne processing round completed...\n" );
  }
  uint32_t endCounter, endTimer;
  c_timer <: 3;
  c_timer :> endCounter;
  c_timer :> endTimer;
  printf("Processing complete in time:: %f\n", timeInSeconds(endCounter, endTimer, 10000000) - timeInSeconds(startCounter, startTimer, 10000000));
  for(int x = 0; x < IMWD; x++)
  {
      for(int y = 0; y < IMHT; y++)
      {
          c_out <: (uchar)grid[x][y];
      }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in)
{
  int res;
  uchar line[ IMWD ];

  //Open PGM file
  printf( "DataOutStream: Start...\n" );
  res = _openoutpgm( outfname, IMWD, IMHT );
  if( res ) {
    printf( "DataOutStream: Error opening %s\n.", outfname );
    return;
  }

  //Compile each line of the image and write the image line-by-line
  for( int y = 0; y < IMHT; y++ ) {
    for( int x = 0; x < IMWD; x++ ) {
      c_in :> line[ x ];
    }
    _writeoutline( line, IMWD );
    printf( "DataOutStream: Line written...\n" );
  }

  //Close the PGM image
  _closeoutpgm();
  printf( "DataOutStream: Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;
  int tilted = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }
  
  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the orientation x-axis forever
  while (1) {

    //check until new orientation data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt
    if (!tilted) {
      if (x>30) {
        tilted = 1 - tilted;
        toDist <: 1;
      }
    }
  }
}

//Send any random crap and get the counter and then timer value back
//Each counter value is worth <interval> timer values
void Timer(chanend c_timer)
{
    //uint32_t limit = -1u;
    //limit -= 100000;
    uint32_t interval = 10000000;
    //printf("Timer limit = %u\n", limit);
    int counter = 0;
    uint32_t time;
    timer t;
    t :> time;
    while (1)
    {
        select
        {
            case c_timer :> uint32_t x:
                t :> x;
                c_timer <: counter;
                c_timer <: x % interval;
                break;
            case t when timerafter(time) :> uint32_t x:
                //printf("Counter incrementing at t = %u\n", x);
                counter++;
                time += interval;
                break;
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

i2c_master_if i2c[1];               //interface to orientation

char infname[] = "test.pgm";     //put your input image path here
char outfname[] = "testout.pgm"; //put your output image path here
chan c_inIO, c_outIO, c_control, c_timer;    //extend your channel definitions here

par {
    i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    orientation(i2c[0],c_control);        //client thread reading orientation data
    DataInStream(infname, c_inIO);          //thread to read in a PGM image
    DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
    distributor(c_inIO, c_outIO, c_control, c_timer);//thread to coordinate work on image
    Timer(c_timer); //timer thread to keep track of a sensible real world time
  }

  return 0;
}
