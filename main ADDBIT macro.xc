// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include <math.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 1024                  //image height
#define  IMWD 1024                  //image width
#define GENERATE 1 //should the grid be generated or read in
#define ROW_LENGTH (IMWD/32) + (IMWD % 32 != 0)
#define WORKERS 8
#define MAXROUNDS 100
#define infname "64test.pgm"     //put your input image path here
#define outfname "testout.pgm" //put your output image path here
#define ROUNDOUT -1
#define ALIVERATIO 0.4
#define LOWRANDBOUND RAND_MAX*ALIVERATIO

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
        c_writeButtons <: (uchar)1;
    }
  }
}

//controller to decide whether the game should be paused currently
[[combinable]]
void pauseController(chanend c_writeButtons, chanend c_accel, chanend c_pause)
{
    uchar pause = 0;
    while (1)
    {
        select
        {
            //button SW2 pushed
            case c_writeButtons :> pause:
                break;
            //board tilt value changed
            case c_accel :> uchar accelVal:
                if (accelVal == 1)
                {
                    pause = 2;
                }
                else if (accelVal == 0 && pause == 2)
                {
                    pause = 0;
                }
                break;
            //another thread requested a pause value
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

//just allows for LED toggling
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
  if (GENERATE)
  {
      return;
  }
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
    }
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );
  return;
}

#define alive (uchar)255
#define ded (uchar)0

//TODO replace with macro or inline, not sure if inline is the same speed
//uint32_t ADDBIT(uint32_t num, unsigned int index)
//{
//    return num | ((uint32_t)1 << index);
//}

#define ADDBIT(x, index) ((x) | (1 << index))

//takes the timer values and interval the timer is running on and returns the most accurate approximation in seconds
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

//returns the number of bits that should be read from the next integer at position n
int getIntSize(int n)
{
    if (IMWD-n*32>32){
        return 32;
    }
    else return IMWD-n*32; //what does this even do?
}

void readRow(chanend c_in, uint32_t row[ROW_LENGTH])
{
    uchar val;
    for (int i = 0; i < ROW_LENGTH; i++)
    {
        uint32_t num = 0;
        //read in from file
        for( int x = 0; x < 32; x++ ) { //go through each pixel per line teehee
            c_in :> val;                    //read the pixel value
            //add a bit to the integer at the index
            if (!val == 0)
            {
                num = ADDBIT(num, x % 32);
            }
        }
        row[i] = num;
    }
}

void sendRow(chanend c_out, uint32_t row[ROW_LENGTH])
{
    for (int i = 0; i < ROW_LENGTH; i++)
    {
        c_out <: row[i];
    }
}

void readImage(chanend wcs[WORKERS], chanend c_in)
{
    //pai
    //yes
    //got a pai
    //some code
    uint32_t firstWorker [IMHT/WORKERS + 1][ROW_LENGTH];
      for (int r = 0; r < IMHT/WORKERS + 1; r++)
      {
          readRow(c_in, firstWorker[r]);
      }
      uint32_t row[ROW_LENGTH];
      //send last processing rows of first worker to next worker
      sendRow(wcs[1], firstWorker[IMHT/WORKERS-1]);
      sendRow(wcs[1], firstWorker[IMHT/WORKERS]);
      for (int r = IMHT/WORKERS + 1; r < IMHT-1; r++)
      {
          readRow(c_in, row);
          //send the row to the worker that will actually process it
          sendRow(wcs[r / (IMHT/WORKERS)], row);
          //before a join
          if (((r + 1) % (IMHT/WORKERS)) == 0)
          {
              sendRow(wcs[(r + 2) / (IMHT/WORKERS)], row);
          }
          //after a join
          else if (((r + 1) % (IMHT/WORKERS)) == 1)
          {
              sendRow(wcs[(r / (IMHT/WORKERS)) - 1], row);
          }
      }
      readRow(c_in, row);
      //send the last row to the last worker to process it
      sendRow(wcs[WORKERS-1],row);
      //send the last row to the first worker to not process it
      sendRow(wcs[0],row);
      //send the very first row to the last worker to not process it
      sendRow(wcs[WORKERS - 1], firstWorker[0]);
      //send all other rows to the first worker
      for (int r = 0; r < IMHT/WORKERS + 1; r++)
      {
          sendRow(wcs[0], firstWorker[r]);
      }
}

void generateImage(chanend wcs[WORKERS], chanend c_timer)
{
      //for each worker
      for (int w = 0; w < WORKERS; w++)
      {
          //for each row in worker
          for (int r = 0; r < IMWD/WORKERS + 2; r++)
          {
              //generate each integer in the row
              for (int i = 0; i < ROW_LENGTH; i++)
              {
                  uint32_t value=0;
                  for (int x=0; x<32;x++){
                      if (rand()<LOWRANDBOUND){
                          value=ADDBIT(value,x);
                      }
                  }
                  wcs[w]<: value;
              }
          }
      }
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
  //Starting up and wait for button press
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
  printf( "Waiting for SW1\n" );
  int r = 0;
  while (r != 14)
  {
      c_buttons :> r;
  }

  //Read in and do something with your image values.
  printf( "Reading image...\n" );
  c_leds <: (uchar)4;

  ///////////////////////////////////////////////////////////
  //        provide workers with initial values            //
  ///////////////////////////////////////////////////////////
  if (GENERATE)
  {
      generateImage(wcs, c_timer);
  }
  else
  {
      readImage(wcs, c_in);
  }

  printf("Processing starting\n");

  c_leds <: (uchar)4;
  //get start time before processing
  uint32_t startCounter, startTimer;
  c_timer <: 3;
  c_timer :> startCounter;
  c_timer :> startTimer;

  int rounds = 0;
  //main processing ιθθρ
  while (rounds < MAXROUNDS)
  {
      //toggle status LED
      c_leds <: (uchar)1;
      //count the number of workers that have replied to the distributor so far
      int workersReplied = 0;
      //first row received is 'stored at w, second row at w + WORKERS
      uint32_t edgeRows[WORKERS * 2][ROW_LENGTH];
      while (workersReplied < WORKERS)
      {
          select
          {
              //read in any worker that can send
              case wcs[int w] :> uint32_t x:
                  workersReplied++;
                  edgeRows[w][0] = x;
                  for (int i = 1; i < ROW_LENGTH; i++)
                  {
                      wcs[w] :> edgeRows[w][i];
                  }
                  for (int i = 0; i < ROW_LENGTH; i++)
                  {
                      wcs[w] :> edgeRows[w + WORKERS][i];
                  }
                  break;
          }
      }
      workersReplied = 0;

      //send the edges back to the other workers
      for (int w = 0; w < WORKERS; w++)
      {
          for (int i = 0; i < ROW_LENGTH; i++)
          {
              wcs[w] <: edgeRows[getPreviousWorker(w)+ WORKERS][i];
          }
          for (int i = 0; i < ROW_LENGTH; i++)
          {
              wcs[w] <: edgeRows[getNextWorker(w)][i];
          }
      }
      rounds++;
      //FIX THIS YOU DEGENERATE SLEEP DEPRIVED SKELETON
      //OR THE CRAZY GREEK ONE, YOU COULD ALSO FIX THIS ιθθρ
      uchar pause = 0;
      //check if execution should pause
      c_pause <: (uchar)37;
      c_pause :> pause;
      //print out on some round
      if (rounds == ROUNDOUT )
      {
          pause = 1;
      }
      for (int i = 0; i < WORKERS; i++)
      {
          wcs[i] <: pause;
      }
      if (pause != 0)
      {
          uchar oldPause = pause;
          //turn off processing LED
          c_leds <: (uchar)1;

          if (pause == 1) //output button is push
          {
              printf("Outputting to file\n");
              c_leds <: (uchar)2;
              //for each worker
              for (int w = 0; w < WORKERS; w++)
              {
                  int rows = IMHT/WORKERS;
                  //for each row
                  for (int r = 0; r < rows; r++)
                  {
                      //for each uint32_t in the row
                      for (int n = 0; n < ROW_LENGTH; n++)
                      {
                          uint32_t x;
                          wcs[w] :> x; //read in from worker channel
                          uchar ffs = getIntSize(n);
                          for (int i = 0; i < ffs; i++)
                          {
                              if (x % 2) //alive
                              {
                                  c_out <: (uchar)255;
                              }
                              else //ded
                              {
                                  c_out <: (uchar)0;
                              }
                              x /= 2;
                          }
                      }
                  }
              }

          }
          else if (pause == 2) //board is tilted, print number of alive cells
          {
              printf("Board is now TILTED\n");
              c_leds <: (uchar)8;
              int aliveCount = 0;
              int x;
              for (int w = 0; w < WORKERS; w++) //get each worker's cell count
              {
                  wcs[w] :> x;
                  aliveCount += x;
              }
              printf("Number of alive cells %i\n", aliveCount);
          }
          //wait for either board to not be tilted or button not be pressed
          while(pause != 0)
          {
              printf("Waiting for unpause\n");
              c_pause <: (uchar)37;
              c_pause :> pause;
              delay_milliseconds(100); //love that this exists
          }
          if (oldPause == 1)
          {
              c_leds <: (uchar)2;
          }
          else if (oldPause == 2)
          {
              //toggle the red LED off
              c_leds <: (uchar)8;
          }
      }
      c_leds <: (uchar)1;
  }

  uint32_t endCounter, endTimer;

  c_timer <: 3;
  c_timer :> endCounter;
  c_timer :> endTimer;
  printf("Processing complete in time: %f\n", timeInSeconds(endCounter, endTimer, 10000000) - timeInSeconds(startCounter, startTimer, 10000000));
}

//check if cell at index is alive
int checkAlive(int r, int i, uint32_t rows[IMWD/WORKERS + 2][ROW_LENGTH])
{
    return rows[r][i / 32] & (1 << (i % 32));
}

//evaluate if cell at row r, index i should be alive next round
uchar evaluate(int r, int i, uint32_t rows[IMWD/WORKERS + 2][ROW_LENGTH])
{
    int neighbors = 0;
    //go over neighboring rows
    for (int y = -1; y < 2; y++)
    {
        //go back and forth along rows
        for (int x = -1; x < 2; x++)
        {
            //not the current cell
            if (!((x == 0) && (0 == y)))
            {
                if (checkAlive(r + y, (i + x + IMWD) % IMWD, rows)) //cell is alive
                {
                    neighbors++;
                }
            }
        }
    }
    if (checkAlive(r, i, rows))
    {
        if (neighbors <= 3 && neighbors >= 2) //stay alive
        {
            return 1;
        }
    }
    else
    {
        if (neighbors == 3) //become alive
        {
            return 1;
        }
    }
    return 0;
}

void Worker(chanend channel, int id)
{
    uint32_t rows[IMWD/WORKERS + 2][ROW_LENGTH];
    //get intial grid values
    for (int r = 0; r < IMWD/WORKERS + 2; r++)
    {
        for (int i = 0; i < ROW_LENGTH; i++)
        {
            channel :> rows[r][i];
        }
    }
    //main processing ιθθρ
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
    //ιθθρ brother
    while (1)
    {
        //initialize new array
        uint32_t rowsNew[IMWD/WORKERS + 2][ROW_LENGTH];
        for (int y = 0; y < IMWD/WORKERS + 2; y++)
        {
            for (int x = 0; x < ROW_LENGTH; x++)
            {
                rowsNew[y][x] = (uint32_t)0;
            }
        }
        //each row
        for (int r = 1; r <= IMWD/WORKERS; r++)
        {
            //each cell
            for (int i = 0; i < IMWD; i++)
            {
                if (evaluate(r, i, rows))
                {
                    rowsNew[r][i / 32] = ADDBIT(rowsNew[r][i / 32], i % 32);
                }
            }
        }
        //clone array
        for (int y = 0; y < IMWD/WORKERS + 2; y++)
        {
            for (int x = 0; x < ROW_LENGTH; x++)
            {
                rows[y][x] = rowsNew[y][x];
            }
        }
        //send out 1st and (n-1)th rows
        for (int i = 0; i < ROW_LENGTH; i++)
        {
            channel <: rows[1][i];
        }
        for (int i = 0; i < ROW_LENGTH; i++)
        {
            channel <: rows[IMWD/WORKERS][i];
        }
        //read back 0th and nth rows
        for (int i = 0; i < ROW_LENGTH; i++)
        {
            channel :> rows[0][i];
        }
        for (int i = 0; i < ROW_LENGTH; i++)
        {
            channel :> rows[IMWD/WORKERS + 1][i];
        }
        uchar pause;
        channel :> pause;
        //send all the rows processed to distributor
        if (pause == 1)
        {
            for (int r = 1; r < IMWD/WORKERS + 1; r++)
            {
                for (int n = 0; n < ROW_LENGTH; n++)
                {
                    channel <: rows[r][n];
                }
            }
        }
        //send number of live rows to distributor
        else if (pause == 2)
        {
            int count = 0;
            for (int r = 1; r < IMWD/WORKERS + 1; r++)
            {
                for (int n = 0; n < ROW_LENGTH; n++)
                {
                    uint32_t x = rows[r][n];
                    for (int i = 0; i < getIntSize(n); i++)
                    {
                        if (x % 2) //TODO - change to checkalive
                        {
                            count++;
                        }
                    }
                }
            }
            channel <: count;
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
  int generation = 0;
  while (1)
  {
      int res;
        uchar line[ IMWD ];

        //Open PGM file
        printf( "DataOutStream: Start...\n" );
        char filename[20];
        sprintf(filename, "testout%i.pgm", generation);
        res = _openoutpgm(filename, IMWD, IMHT );
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
          //printf( "DataOutStream: Line written...\n" );
        }

        //Close the PGM image
        _closeoutpgm();
        printf( "DataOutStream: Done...\n" );
        generation++;
  }
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
    uint32_t interval = 10000000;
    int counter = 0;
    uint32_t time;
    timer t;
    t :> time;
    while (1)
    {
        select
        {
            //something requested a timer value
            case c_timer :> uint32_t x:
                t :> x;
                c_timer <: counter;
                c_timer <: x % interval;
                break;
            //increment interval time
            case t when timerafter(time) :> uint32_t x:
                counter++;
                time += interval;
                break;
        }
    }
}

//void test()
//{
//    uint32_t n = 0;
//    unsigned int index = 6;
//    printf("bit inserted at %u = %u\n", index, n = ADDBIT(n, index));
//    index = 17;
//    printf("bit inserted at %u = %u\n", index, n = ADDBIT(n, index));
//    printf("\n");
//}

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
    on tile[0].core[0]: LEDController(c_leds); //basically just gives us toggleable LEDs, probably more trouble than is worth
    on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    on tile[0]: orientation(i2c[0], c_accel);        //client thread reading orientation data
    on tile[0]: { //we can run these sequentially as the datainstream only needs to run once
        DataInStream(c_inIO);
        DataOutStream(c_outIO);
    }
    on tile[0]: distributor(c_inIO, c_outIO, c_timer, workerChans, c_leds, c_buttons, c_stop);//thread to coordinate work on image
    on tile[0]: buttonListener(buttons, c_buttons, c_pauseLink); //listens to buttons, vat vanderful musik zey make
    on tile[0]: pauseController(c_pauseLink, c_accel, c_stop); //distributes pause value
    //on tile[0]: test();
    on tile[0]: Worker(workerChans[0], 0);
    par (int i = 1; i < WORKERS; i++) //start workers in order, giving them IDs for debug purposes
    {
        on tile[1]: Worker(workerChans[i], i);
    }
  }

  return 0;
}
