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
#define rowLength (IMWD/32) + (IMWD % 32 != 0)
#define WORKERS 8
#define infname "diag.pgm"     //put your input image path here
#define outfname "testout.pgm" //put your output image path here

typedef unsigned char uchar;      //using uchar as shorthand

on tile[0]: port p_scl = XS1_PORT_1E;         //interface ports to orientation
on tile[0]: port p_sda = XS1_PORT_1F;

on tile[0] : in port buttons = XS1_PORT_4E; //buttons

//1st bit...separate green LED
//2nd bit...blue LED
//3rd bit...green LED
//4th bit...red LED
on tile[0] : out port leds = XS1_PORT_4F;

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

void buttonListener(in port b, chanend c_out) {
  int r;
  while (1) {
    b when pinseq(15)  :> r;    // check that no button is pressed
    b when pinsneq(15) :> r;    // check if some buttons are pressed
    if ((r==13) || (r==14))     // if either button is pressed
    c_out <: r;             // send button pattern to userAnt
  }
}

void LEDController(chanend c_in)
{
    int current = 0;
    while (1)
    {
        select
        {
            case c_in :> int x:
                current ^= x;
                leds <: current;
                break;
        }
    }
}
/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(chanend c_out)
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
      //printf( "-%4.1d ", line[ x ] ); //show image values
    }
    //printf( "\n" );
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
void distributor(chanend c_in, chanend c_out, chanend fromAcc, chanend c_timer, chanend wcs[WORKERS], chanend c_leds)
{
  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
  printf( "Waiting for SW1\n" );
  //fromAcc :> int value;
  int r = 0;
  while (r != 14)
  {
      buttons when pinsneq(15) :> r;
      printf("%i\n", r);
  }

  //Read in and do something with your image values.
  //unsigned char grid[IMHT][IMWD];
  printf( "Reading image...\n" );
  c_leds <: 4u;

  uint32_t rows[IMHT][rowLength];
  uchar val;
  for( int y = 0; y < IMHT; y++ ) {   //go through all lines
    for (int i = 0; i < rowLength; i++)
    {
        rows[y][i] = 0u;
    }
    for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
      c_in :> val;                    //read the pixel value
      //add a bit to the integer at the index
      rows[y][x/32] |= ((uint32_t)(val != 0) << x % 32);
    }
  }

  c_leds <: 4u;

  printf("First int in first row = %u\n", rows[0][0]);
  //get start time before processing
  uint32_t startCounter, startTimer;
  c_timer <: 3;
  c_timer :> startCounter;
  c_timer :> startTimer;

  //provide workers with initial values
  //for each worker
  for (int w = 0; w < WORKERS; w++)
  {
      //for each row in worker
      for (int r = 0; r < IMWD/WORKERS + 2; r++)
      {
          //adjust row number to allow for previous workers and shifting it back one
          int rowNo = r + (w * IMWD/WORKERS) -1;
          //allow for wrap arounds
          if (rowNo < 0)
          {
              rowNo = IMHT - 1;
          }
          else if (rowNo >= IMHT)
          {
              rowNo = 0;
          }
          //export each integer in the row
          for (int i = 0; i < rowLength; i++)
          {
              wcs[w] <: rows[rowNo][i];
          }
      }
  }

  //do not delete ιθθρ!
  //main processing ιθθρ
  while (1)
  {
      //toggle status LED
      c_leds <: 1;
      for (int w = 0; w < WORKERS; w++)
      {
          //allow for wrap
          unsigned char prevWorker = w - 1 + (w == 0) * WORKERS;
          unsigned char nextWorker = w + 1 - (w == WORKERS -1) * WORKERS;
          //transfer first and last rows to the next workers along
          uint32_t temp;
          for (int i = 0; i < rowLength; i++)
          {
              wcs[w] :> temp;
              wcs[prevWorker] <: temp;
          }
          for (int i = 0; i < rowLength; i++)
          {
              wcs[i] :> temp;
              wcs[nextWorker] <: temp;
          }
      }
      select
      {
          case wcs[w] :> uint32_t x:
              for (int i = 0; i < rowLength; i++)
              {

              }
      }
  }

//  int maxrounds = 20;
//  for (int rounds = 0; rounds < maxrounds; rounds++)
//  {
//      //find which cells live or die
//      unsigned char newgrid[IMHT][IMWD];
//      for (int x = 0; x < IMWD; x++)
//      {
//          for (int y = 0; y < IMHT; y++)
//          {
//              unsigned char neighbors = 0;
//              neighbors += checkAlive(x + 1, y, grid);
//              neighbors += checkAlive(x + 1, y + 1, grid);
//              neighbors += checkAlive(x + 1, y - 1, grid);
//              neighbors += checkAlive(x - 1, y, grid);
//              neighbors += checkAlive(x - 1, y + 1, grid);
//              neighbors += checkAlive(x - 1, y - 1, grid);
//              neighbors += checkAlive(x, y + 1, grid);
//              neighbors += checkAlive(x, y - 1, grid);
//              if (grid[x][y] == alive)
//              {
//                  if (neighbors > 3 || neighbors < 2)
//                  {
//                      newgrid[x][y] = ded;
//                  }
//                  else
//                  {
//                      newgrid[x][y] = alive;
//                  }
//              }
//              else if (neighbors == 3)
//              {
//                  newgrid[x][y] = alive;
//              }
//              else
//              {
//                  newgrid[x][y] = ded;
//              }
//          }
//      }
//      //printf("--------------------------------------------------\n");
//      for (int x = 0; x < IMWD; x++)
//      {
//          for (int y = 0; y < IMHT; y++)
//          {
//              if ((uchar)newgrid[x][y] == alive)
//              {
//                  //printf(" X ");
//              }
//              else if ((uchar)newgrid[x][y] == ded)
//              {
//                  //printf(" - ");
//              }
//              else
//              {
//                  //printf("%u", (uchar)newgrid[x][y]);
//              }
//              grid[x][y] = newgrid[x][y];
//          }
//          //printf("\n");
//      }
//      //printf("--------------------------------------------------\n");
//      //c_out <: (uchar)( val ^ 0xFF ); //send some modified pixel out
//      //printf( "\nOne processing round completed...\n" );
//  }
  uint32_t endCounter, endTimer;

  c_timer <: 3;
  c_timer :> endCounter;
  c_timer :> endTimer;
  printf("Processing complete in time: %f\n", timeInSeconds(endCounter, endTimer, 10000000) - timeInSeconds(startCounter, startTimer, 10000000));
//  for(int y = 0; y < IMHT; y++)
//  {
//      for(int x = 0; x < IMWD; x++)
//      {
//          if (grid[x][y] == alive)
//          {
//              c_out <: (uchar)255;
//          }
//          else
//          {
//              c_out <: (uchar)0;
//          }
//          //c_out <: (uchar)grid[x][y];
//      }
//  }
}

void Worker(chanend channel)
{
    uint32_t rows[IMWD/WORKERS + 2][rowLength];
    //get intial grid values
    for (int r = 0; r < IMWD/WORKERS + 2; r++)
    {
        for (int i = 0; i < rowLength; i++)
        {
            channel :> rows[r][i];
        }
        printf("Worker received int: %u\n", rows[r][0]);
    }
    //main processing loop
    while (1)
    {
        for (int i = 0; i < rowLength; i++)
        {
            channel <: rows[0][i];
        }
        for (int i = 0; i < rowLength; i++)
        {
            channel <: rows[IMWD/WORKERS + 2 - 1][i];
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(chanend c_in)
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

chan c_inIO, c_outIO, c_control, c_timer, c_leds;    //extend your channel definitions here
chan workerChans[WORKERS];
par {
    on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    on tile[0]: orientation(i2c[0],c_control);        //client thread reading orientation data
    on tile[0]: DataInStream(c_inIO);          //thread to read in a PGM image
    on tile[0]: DataOutStream(c_outIO);       //thread to write out a PGM image
    on tile[0]: distributor(c_inIO, c_outIO, c_control, c_timer, workerChans, c_leds);//thread to coordinate work on image
    on tile[0]: Timer(c_timer); //timer thread to keep track of a sensible real world time
    on tile[0]: LEDController(c_leds);
    par (int i = 0; i < WORKERS; i++)
    {
        on tile[1]: Worker(workerChans[i]);
    }
  }

  return 0;
}
