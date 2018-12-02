// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include <math.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 67                  //image height
#define  IMWD 67                  //image width
#define rowLength (IMWD/32) + (IMWD % 32 != 0)
#define WORKERS 8
#define infname "one.pgm"     //put your input image path here
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

void buttonListener(in port b, chanend c_out, chanend c_writeButtons) {
  int r;
  while (1) {
    b when pinseq(15)  :> r;    // check that no button is pressed
    b when pinsneq(15) :> r;    // check if some buttons are pressed
    if (r==14)
    {
        c_out <: r;             // send button pattern to distributor
    }
    else if (r==13)
    {
        //printf("button 13 pushed\n");
        c_writeButtons <: (uchar)1;
    }
  }
}

[[combinable]]
void pauseController(chanend c_writeButtons, chanend c_accel, chanend c_pause)
{
    uchar pause = 0;
    while (1)
    {
        select
        {
            case c_writeButtons :> pause:
                break;
            case c_accel :> uchar accelVal:
                printf("Received accelVal of %u\n", accelVal);
                if (accelVal == 1)
                {
                    pause = 2;
                }
                else if (accelVal == 0 && pause == 2)
                {
                    pause = 0;
                }
                printf("pauseController pause value: %u\n", pause);
                break;
            case c_pause :> uchar x:
                c_pause <: pause;
                if (pause == 1)
                {
                    pause = 0;
                }
                break;
        }
    }
}

[[combinable]]
void LEDController(chanend c_in)
{
    uchar current = 0;
    while (1)
    {
        select
        {
            case c_in :> uchar x:
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
//nicked from https://stackoverflow.com/questions/29787310/does-pow-work-for-int-data-type-in-c as pow() seems to bork pretty hard for ints
int int_pow(int base, int exp)
{
    int result = 1;
    while (exp)
    {
        if (exp & 1)
           result *= base;
        exp /= 2;
        base *= base;
    }
    return result;
}
double timeInSeconds(uint32_t counter, uint32_t timerValue, uint32_t interval)
{
    return (counter * ((double)interval / (double)100000000)) + timerValue / (double)100000000;
}
int getPreviousWorker(int w)
{
    return w - 1 + (w == 0) * WORKERS;
}
int getNextWorker(int w)
{
    return w + 1 - (w == WORKERS -1) * WORKERS;
}
/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend c_out, chanend c_timer, chanend wcs[WORKERS], chanend c_leds, chanend c_buttons, chanend c_pause)
{
  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
  printf( "Waiting for SW1\n" );
  //fromAcc :> int value;
  int r = 0;
  while (r != 14)
  {
      c_buttons :> r;
      //printf("%i\n", r);
  }

  //Read in and do something with your image values.
  //unsigned char grid[IMHT][IMWD];
  printf( "Reading image...\n" );
  c_leds <: (uchar)4;

  uint32_t rows[IMHT][rowLength];
  uchar val;
  for( int y = 0; y < IMHT; y++ ) {   //go through all lines
    for (int i = 0; i < rowLength; i++)
    {
        rows[y][i] = 0u;
    }
    for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line teehee
      c_in :> val;                    //read the pixel value
      //add a bit to the integer at the index
      rows[y][x/32] |= ((uint32_t)(val != 0) << x % 32);
    }
  }

  c_leds <: (uchar)4;

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

  //uchar stop = 0;
  //do not delete loop! #bestadvice
  //main processing loop
  while (1)
  {
      //toggle status LED
      c_leds <: (uchar)1;
      int workersReplied = 0;
      //first row received is stored at w, second row at w * 2
      uint32_t edgeRows[WORKERS * 2][rowLength];
      while (workersReplied < WORKERS)
      {
          select
          {
              case wcs[int w] :> uint32_t x:
                  //printf("Worker %i replied to distributer\n", w);
                  workersReplied++;
                  edgeRows[w][0] = x;
                  for (int i = 1; i < rowLength; i++)
                  {
                      wcs[w] :> edgeRows[w][i];
                  }
                  for (int i = 0; i < rowLength; i++)
                  {
                      wcs[w] :> edgeRows[w * 2][i];
                  }
                  break;
          }
      }
      workersReplied = 0;
      //printf("All workers replied to distributer\n");

      for (int w = 0; w < WORKERS; w++)
      {
          for (int i = 0; i < rowLength; i++)
          {
              wcs[w] <: edgeRows[getPreviousWorker(w) * 2][i];
          }
          for (int i = 0; i < rowLength; i++)
          {
              wcs[w] <: edgeRows[getNextWorker(w)][i];
          }
      }
      //printf("All workers have been sent their shit\n");
      printf("Round complete\n");
      c_pause <: (uchar)37;
      uchar pause;
      c_pause :> pause;
      for (int i = 0; i < WORKERS; i++)
      {
          wcs[i] <: pause;
      }
      if (pause != 0)
      {
          if (pause == 1)
          {
              for (int w = 0; w < WORKERS; w++)
              {
                  int rows = IMHT/WORKERS;
                  for (int r = 0; r < rows; r++)
                  {
                      for (int n = 0; n < rowLength; n++)
                      {
                          uint32_t x;
                          wcs[w] :> x;
                          //printf("Distributor received: %u\n", x);
                          uchar ffs;//code
                          if (IMWD-n*32>32){
                              ffs=32;
                          }
                          else ffs=IMWD-n*32;
                          for (int i = 0; i < ffs; i++)
                          {
                              //printf("divisor = %i\n", divisor);
                              if ((x % 2))
                              {
                                  c_out <: (uchar)255;
                              }
                              else
                              {
                                  c_out <: (uchar)0;
                              }
                              x /= 2;

                          }
                      }
                  }
              }
          }
          else if (pause == 2)
          {
              printf("Board is now TILTED\n");
              c_leds <: (uchar)8;
          }
          while(pause != 0);
          {
              c_pause <: (uchar)1;
              c_pause :> pause;
              printf("Pause value is currently %u, waiting for pause to be 0\n", pause);
          }
          printf("Board no longer TILTED\n");

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
        //printf("Worker received int: %u\n", rows[r][0]);
    }
    //main processing loop
    //shit
    //more shjit
    //i can't computer send help
    //https://old.reddit.com/r/Ooer/
    //it's one am
    //AAAAAAAAAAAAAAAAAAAA
    //is that where i add the shit?
    //i don't know, he's not telling me
    // "add the fucking shit"
    //okay
    //loop brother
    //uchar stop = 0;
    while (1)
    {
        //send out 1th and (n-1)th rows
        for (int i = 0; i < rowLength; i++)
        {
            channel <: rows[1][i];
        }
        for (int i = 0; i < rowLength; i++)
        {
            channel <: rows[IMWD/WORKERS][i];
        }
        //read back 0th and nth rows
        for (int i = 0; i < rowLength; i++)
        {
            channel :> rows[0][i];
        }
        for (int i = 0; i < rowLength; i++)
        {
            channel :> rows[IMWD/WORKERS+1][i];
        }
        uchar stop;
        channel :> stop;
        if (stop)
        {
            for (int r = 1; r < IMWD/WORKERS + 1; r++)
            {
                for (int n = 0; n < rowLength; n++)
                {
                    channel <: rows[r][n];
                }
            }
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
void orientation( client interface i2c_master_if i2c, chanend c_out) {
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
    //printf("x tilt value=%i\n", x);
    //send signal to distributor after first tilt
    //nah jus send whatever m8
    if (abs(x) > 30) {
        if (tilted == 0)
        {
            c_out <: (uchar)1;
            tilted = 1;
        }
    }
    else
    {
        if (tilted == 1)
        {
            tilted = 0;
            c_out <: (uchar)0;
        }
    }
  }
}

//Send any random crap and get the counter and then timer value back
//Each counter value is worth <interval> timer values
[[combinable]]
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

chan c_inIO, c_outIO, c_timer, c_leds, c_buttons, c_stop, c_pauseLink, c_accel;    //extend your channel definitions here
chan workerChans[WORKERS];
par {
    on tile[0].core[0]: Timer(c_timer); //timer thread to keep track of a sensible real world time
    on tile[0].core[0]: LEDController(c_leds);
    on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    on tile[0]: orientation(i2c[0], c_accel);        //client thread reading orientation data
    on tile[0]: DataInStream(c_inIO);          //thread to read in a PGM image
    on tile[0]: DataOutStream(c_outIO);       //thread to write out a PGM image
    on tile[0]: distributor(c_inIO, c_outIO, c_timer, workerChans, c_leds, c_buttons, c_stop);//thread to coordinate work on image
    on tile[0]: buttonListener(buttons, c_buttons, c_pauseLink);
    on tile[0]: pauseController(c_pauseLink, c_accel, c_stop);
    par (int i = 0; i < WORKERS; i++)
    {
        on tile[1]: Worker(workerChans[i]);
    }
  }

  return 0;
}
