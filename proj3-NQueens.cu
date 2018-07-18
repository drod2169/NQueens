/* ==================================================================
  Programmers: Conner Wulf (connerwulf@mail.usf.edu),
               Derek Rodriguez (derek23@mail.usf.edu)
	             David Hoambrecker (david106@mail.usf.edu)

  To Compile use: nvcc -o queens proj3-Nqueens.cu
  you can specify the board size by compiling with: nvcc  -o queens proj3-Nqueens.cu -DNUM=a
  * where a must be >= 4 and <= 22

  The program reads in 2 arguments, the first is the number of tuples generated by blockIdx.x
                                    the second is the number of groups of columns, size multiple of board size.
                                    ex. ./queens 4 1000 (based on board size is 12)
   ==================================================================
*/

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <sys/time.h>
#include <iostream>
#include <cuda_runtime.h>
#include <cuda.h>
#include <vector>

using namespace std;
static int total = 0;
unsigned long count = 0;
struct timezone Idunno;
struct timeval startTime, endTime;
long *answer;

 #ifndef NUM
 #define NUM 4
 #endif
 __device__ void sumBlocks(long *a, int nBX, int nBY);

 __device__ void findSum(long *a, int nBX, int nBY)
 {
   int num_Blocks = gridDim.x *gridDim.y;
   int gridRowSize = powf(NUM, nBX);
   long total = 0;

   if(NUM % 2 == 0)
   {
       for(int t = 0; t < num_Blocks; t++)
       {
         total += a[t];
         printf("%li\n", a[t]);
       }
       total *= 2;
       printf("%li\n", total);
   }

   else
   {
     int SegBlockNum = num_Blocks / nBY;

     for(int q = 0; q < nBY; q++)
     {

       int begin = q* SegBlockNum;

       for(int b = begin; b < begin + SegBlockNum -gridRowSize; b++)
       {
         total += a[b];
       }
     }
     total *= 2;

     for(int f = 0; f < nBY; f++)
     {

       for( int e = f * SegBlockNum + SegBlockNum - gridRowSize; e < f * SegBlockNum + SegBlockNum; e++)
       {
         total += a[e];
       }
     }
   }

   a[gridDim.x * blockIdx.y + blockIdx.x] = 0;
   a[gridDim.x * blockIdx.y + blockIdx.x] = total;



 }

//CPU helper function to test is a queen can be placed
int isAllowed(int **board, int row, int col, int n)
{
  int x,y;

  //left check
  for (x = 0; x < col; x++)
  {
    if(board[row][x] == 1)
    {
      return 0;
    }
  }
  //check left diagonal up
  for(x = row, y = col; x >= 0 && y >= 0; x--, y--)
    {
      if (board[x][y] == 1)
      {
        return 0;
      }
    }
  for(x = row, y = col; x < n && y >= 0; x++, y--)
  {
    if (board[x][y] == 1)
    {
      return 0;
    }
  }
 return 1;
}
// CPU Solver for N-queens problem
int Solver(int **board, int col, int n)
{
  if (col >= n)
  {
    total++;
    return 1;
  }

  int nextState = 0;

  for(int k = 0; k < n; k++)
  {
    if (isAllowed(board,k,col, n))
    {
      board[k][col] = 1;
      nextState = Solver(board, col + 1, n);
      board[k][col] = 0;
    }
  }
  return nextState;
}

// GPU parallel kernel for N-Queens
__global__ void kernel(long *d_d_answer, int SegSize, int nBX, int nBY, int genNum, int GPUSum)
{
  __shared__ long sol[NUM][NUM];
  __shared__ char tup[NUM][NUM][NUM];

  int wrongCount = 0;
  
  int totalGenerated = powf(NUM, genNum);
  int blockYSeg = blockIdx.y / SegSize;
  int workLoad = totalGenerated / nBY;
  int runOff = totalGenerated - workLoad * nBY;




  int temp = blockIdx.x;
  for(int x = 1; x <=nBX; x++)
  {
    tup[threadIdx.x][threadIdx.y][x] = temp % NUM;
    temp = temp / NUM;
  }
  int tupCount = nBX;
  tup[threadIdx.x][threadIdx.y][++tupCount] = threadIdx.x;
  tup[threadIdx.x][threadIdx.y][++tupCount] = threadIdx.y;
  for(int k = tupCount; k > 0; k--)
  {
    for(int m = k - 1, counter = 1; m >= 0; counter++, m--)
    {
      //Checks diagonal left, down
      wrongCount += (tup[threadIdx.x][threadIdx.y][k] + counter) == tup[threadIdx.x][threadIdx.y][m];
      //Checks row its in
      wrongCount += tup[threadIdx.x][threadIdx.y][k] == tup[threadIdx.x][threadIdx.y][m];
      // Checks diagonal left, up
      wrongCount  += (tup[threadIdx.x][threadIdx.y][k] - counter) == tup[threadIdx.x][threadIdx.y][m];

    }
  }

  if (wrongCount == 0)
  {
    int begin = blockYSeg * workLoad;
    for(int c = begin; c < begin + workLoad + (blockYSeg == nBY - 1) * runOff; c++)
    {
      //last values is made in tuple, convert and store to tup array
      int temp = c;
      for(int q = 0, z = tupCount + 1; q < genNum; z++, q++)
      {
        tup[threadIdx.x][threadIdx.y][z] = temp % NUM;
        temp = temp / NUM;
      }

      //checks that the genNum tuple values are indeed unique (saves work overall)
      for(int a = 0; a < genNum && wrongCount == 0; a++){
				for(int b = 0; b < genNum && wrongCount == 0; b++){
					wrongCount += tup[threadIdx.x][threadIdx.y][tupCount + 1 + a] == tup[threadIdx.x][threadIdx.y][tupCount + 1 + b] && a != b;
        }
			}

      for(int k = NUM -1; k > wrongCount * NUM; k--)
      {
        for(int m = k - 1, counter = 1; m >= 0; m--, counter++)
        {
          //Checks diagonal left, down
          wrongCount += (tup[threadIdx.x][threadIdx.y][k] + counter) == tup[threadIdx.x][threadIdx.y][m];
          //Checks row its in
          wrongCount += tup[threadIdx.x][threadIdx.y][k] == tup[threadIdx.x][threadIdx.y][m];
          // Checks diagonal left, up
          wrongCount += (tup[threadIdx.x][threadIdx.y][k] - counter) == tup[threadIdx.x][threadIdx.y][m];
        }
      }
      sol[threadIdx.x][threadIdx.y] += !(wrongCount);

      wrongCount = 0;

    }
  }
  
  __syncthreads();
    // sum all threads in block to get total
  	if(threadIdx.x == 0 && threadIdx.y == 0)
    {

  		long total = 0;

  		for(int i =0; i < NUM; i++){
  			for(int j = 0; j < NUM; j++){
  				total += sol[i][j];
        }
        printf("%d\n", total);
  		}
  		d_answer[gridDim.x * blockIdx.y + blockIdx.x] = total;
    //  printf("%li\n", d_answer[gridDim.x * blockIdx.y + blockIdx.x]);
  	}


  	__syncthreads();

    if(GPUSum == 1 && blockIdx.x == 0 && blockIdx.y == 0 && threadIdx.x == 0 && threadIdx.y == 0)
    {
      //findSum(d_answer, nBX, nBY);
      int numBlocks = gridDim.x * gridDim.y;
      int gridRowSize = powf(NUM, nBX);
      long total = 0;

      if(NUM % 2 == 0)
      {
          for(int t = 0; t < numBlocks; t++)
          {
            total+= d_answer[t];
            //printf("%li\n", d_answer[t]);
          }
          total *= 2;
        //  printf("%li\n", total);
      }

      else
      {
        int SegBlockNum = numBlocks / nBY;

        for(int q = 0; q < nBY; q++)
        {

          int begin = q* SegBlockNum;

          for(int b = begin; b < begin + SegBlockNum -gridRowSize; b++)
          {
            total+= d_answer[b];
          }
        }
        total *= 2;

        for(int f = 0; f < nBY; f++)
        {

          for( int e = f * SegBlockNum + SegBlockNum - gridRowSize; e < f * SegBlockNum + SegBlockNum; e++)
          {
            total += d_answer[e];
          }
        }
      }

      d_answer[gridDim.x * blockIdx.y + blockIdx.x] = 0;
      d_answer[gridDim.x * blockIdx.y + blockIdx.x] = total;
    }
}





double report_running_time() {
	long sec_diff, usec_diff;
	gettimeofday(&endTime, &Idunno);
	sec_diff = endTime.tv_sec - startTime.tv_sec;
	usec_diff= endTime.tv_usec-startTime.tv_usec;
	if(usec_diff < 0) {
		sec_diff --;
		usec_diff += 1000000;
	}
	printf("CPU Time: %ld.%06ld secs\n", sec_diff, usec_diff);
	return (double)(sec_diff*1.0 + usec_diff/1000.0);
}


int main(int argc, char **argv) {

  if(argc < 4) {

    printf("\nError, too few arguments. Usage: ./queens 1 4 1\n");
    return -1;
  }

  const int NUM_TUPLEX = atoi(argv[1]);
  const int NUM_TUPLEY = atoi(argv[2]);
  int GPUSum = atoi(argv[3]);
  const int generatedNum = NUM - 3 - NUM_TUPLEX;
  cudaEvent_t start, stop;
  float elapsedTime;

  if(generatedNum < 0){
    printf("\nThe numbers generated iteratively cannot be less than 0.\n");
    exit(1);
  }

  //ensure N is in the correct range
  if(NUM < 4  || NUM > 22){
    printf("\nN(%d) must be between 4 and 22 inclusive\n", NUM);
    exit(1);
  }
  if(GPUSum != 0 && GPUSum != 1)
  {
    printf("\nThe GPU sum identifier(%d) must be a 0 or 1, only\n", GPUSum);
    exit(1);
  }

  //ensure that at least one of the tuple values is generated by the block's X coordinate value
  if(NUM_TUPLEX < 1){
    printf("\nThe number of tuples generated by each block's X coordinate value must be >= 1\n");
    exit(1);
  }

  	//ensure that the number of Y segments that the numGen work is divided into
  	//is at least one per work segment
  	if(NUM_TUPLEY > pow(NUM, generatedNum)){
  		printf("\n number of groups of columns must be less than or equal to N^(N - 3 - (1st ARG))\n");
  		exit(1);
  	}

  //CPU setup
  int **board;
  board = (int **) malloc(NUM * sizeof(int *));

  for (int i = 0; i < NUM; i++) {
    board[i] = (int *) malloc(NUM * sizeof(int));

  }
  for (int i = 0; i < NUM; i++) {
    for (int j = 0; j < NUM; j++) {
      board[i][j] = 0;

    }
  }

  int WIDTH, HEIGHT, NUM_BLOCKS, YSegmentSize;
  WIDTH = pow(NUM, NUM_TUPLEX);
  YSegmentSize = (NUM / 2) + (NUM % 2);
  HEIGHT = YSegmentSize + NUM_TUPLEY;
  NUM_BLOCKS = WIDTH * HEIGHT;

  answer = new long[NUM_BLOCKS];

  long *d_answer;

  cudaMalloc((void **) &d_answer, sizeof(long) * NUM_BLOCKS);
  int cnt = 0;
  // for(int i = 0; i < NUM_BLOCKS; i++) {
  //   if(answer[i] == 1) {
  //     cnt++;
  //     printf("%d\n", answer[i]);
  //   }
  // }

  // printf(" cnt: %d\n", cnt);
  dim3 block(NUM, NUM); //threads w x h
  dim3 grid(WIDTH, HEIGHT); //blocks w x h

  cudaEventCreate(&start);
  cudaEventCreate(&stop);
  cudaEventRecord(start, 0);

  kernel<<<grid, block>>>(d_answer, YSegmentSize, NUM_TUPLEX, NUM_TUPLEY, generatedNum, GPUSum);
  cudaThreadSynchronize();

  cudaEventRecord(stop, 0);
  cudaEventSynchronize(stop);
  cudaEventElapsedTime(&elapsedTime, start, stop);

  cudaMemcpy(answer,d_answer, sizeof(long) * NUM_BLOCKS, cudaMemcpyDeviceToHost);


const char* errorString = cudaGetErrorString(cudaGetLastError());
printf("GPU Error: %s\n", errorString);


	srand(1);
  gettimeofday(&startTime, &Idunno);
  Solver(board, 0, NUM);


  if(GPUSum == 0)
  {
    printf("\nTotal Solutions(CPU): %d boards\n",total);
  }
  else if (GPUSum == 1)
  {
    printf("\nTotal Solutions(GPU): %li boards\n", answer[0]);
  }

  report_running_time();
  printf("GPU Time: %f secs\n\n", (elapsedTime / 1000.00));

		int sum = 0;
	
		//check if N is even or odd, then calculate sum, which is number of solutions
		if(NUM % 2 == 0){
			for(int i = 0; i < NUM_BLOCKS; i++){ 
				sum+= answer[i];
			}
			sum *= 2;
		}
    else
    {
			int numBlocksPerSeg = NUM_BLOCKS / NUM_TUPLEY;
			int rowSizeOfGrid = pow(NUM, NUM_TUPLEX);
			
			for(int j = 0; j < NUM_TUPLEY; j++){
        int start = j * numBlocksPerSeg;
        printf("%d\n", start);
				for(int i = start; i < start + numBlocksPerSeg - rowSizeOfGrid; i++){ 
        printf("%d\n", answer[i]);
					sum+= answer[i];
				}
			
			}
			sum *= 2;
			
			//add last block row of sums for each Y block
			for(int j = 0; j < NUM_TUPLEY; j++){
				for(int i = j * numBlocksPerSeg + numBlocksPerSeg - rowSizeOfGrid; i < j * numBlocksPerSeg + numBlocksPerSeg; i++){ 
					sum+= answer[i];
				}
      }
      
  }
  printf("\nTotal Solutions: %d boards\n", sum);
  return 0;

}

/* nqueens.cu
 * Jonathan Lehman
 * February 26, 2012
 *  
 * Compile with: nvcc -o nqueens nqueens.cu
 * to get default with _N_ = 4 and numBX = 1 numBY = 1 sumOnGPU = 0
 *
 * Or specify _N_ by compiling with: nvcc -o nqueens nqueens.cu -D_N_=x
 * where x is the board size desired where x must be >= 4 and <= 22
 *
 * and/Or specify numBX by compiling with: nvcc -o nqueens nqueens.cu -DnumBX=y
 * where y is the number of tuple values to be generated by blockIdx.x 
 *	where y must be >= 1 such that N^numBX < maxgridsize (in this case 65535 blocks)
 *
 * and/or specify numBY by compiling with nvcc -o nqueens nqueens.cu -DnumBY=z
 * where z is the number of groups of ((N / 2) + (N % 2)) columns by N^numBX rows that work on the solution
 * essentially, this evenly divides the work of the tuples being generated iteratively by each thread between each group
 *	where z must be <= N^numBX
 *
 * and/or specify whether or not to add the block totals on the GPU or cpu with nvcc -o nqueens nqueens.cu -DsumOnGPU=a
 *	where a is 1 or 0, with 1 doing the sum on the GPU and 0 doing the sum on the CPU
 *
 */

// #include <cuda.h>
// #include <stdio.h>
// #include <math.h>
// #include <sys/time.h>

// __global__ void queen(long*, int);
// __device__ void sumBlocks(long *);
// void checkArgs(int, char**, int);
// void checkGPUCapabilities(int, int, int, int, int);
// double getTime();

// //set board size
// #ifndef _N_
// #define _N_ 8
// #endif

// //set the number of values in the tuple BlockIdx.x should be responsible for
// #ifndef numBX
// #define numBX 1
// #endif
 
// #ifndef numBY
// #define numBY 1
// #endif

// //number of values in tuple to be generated by thread (incrementally)
// //#ifndef numGen
// #define numGen _N_ - 3 - numBX
// //#endif

// //whether or not the sum of blocksums (solution should be summed on GPU or CPU)
// //CPU by default
// //Set to 1 to add on GPU
// #ifndef sumOnGPU
// #define sumOnGPU 0
// #endif


// // Keep track of the gpu time.
// cudaEvent_t start, stop; 
// float elapsedTime;

// // Keep track of the CPU time.
// double startTime, stopTime;
 
// //array for block sums
// long *a;

// int main(int argc, char *argv[]){		

// 	/*check errors with macros*/
	
// 	//ensure number of tuples generated iteratively is not less than 0
// 	if(numGen < 0){
// 		fprintf(stderr, "\nnqeens: The number of values in the tuple generated iteratively cannot be less than 0.\n NumGen = _N_(%d) - 3 - numBX(%d) = %d\n", _N_, numBX, numGen);
// 		exit(1);
// 	}
	
// 	//ensure N is in the correct range
// 	if(_N_ < 4  || _N_ > 22){
// 		fprintf(stderr, "\nnqeens: _N_(%d) must be between 4 and 22 inclusive\n", _N_);
// 		exit(1);
// 	}
	
// 	//ensure that at least one of the tuple values is generated by the block's X coordinate value
// 	if(numBX < 1){
// 		fprintf(stderr, "\nnqeens: The number of tuples generated by each block's X coordinate value (numBX=%d) must be >= 1\n", numBX);
// 		exit(1);
// 	}
	
// 	//ensure that the number of Y segments that the numGen work is divided into
// 	//is at least one per work segment
// 	if(numBY > pow(_N_, numGen)){
// 		fprintf(stderr, "\nnqeens: numBY(%d) must be less than or equal to _N_^numGen(%d)\n", numBY, pow(_N_, numGen));
// 		exit(1);
// 	}
	

// 	long *dev_a;
	
// 	//check validity of arguments (should be no arguments)
// 	checkArgs(argc, argv, 1);
	
// 	int gW, gH, numberBlocks;
	
// 	//calculate grid width based on factor N, 
// 	gW = pow(_N_, numBX);
	
// 	//depends on if N is even or odd
// 	int sizePerYSeg = (_N_ / 2) + (_N_ % 2);
	
// 	gH = sizePerYSeg * numBY;
	
// 	numberBlocks = gW * gH;	
	
// 	//check that GPU can handle arguments
// 	checkGPUCapabilities(gW, gH, _N_, _N_, numberBlocks);
  
// 	/* Initialize the source arrays here. */
//   	a = new long[numberBlocks];  
  	
//   	/* Allocate global device memory. */
//   	cudaMalloc((void **)&dev_a, sizeof(long) * numberBlocks);
  	
//   	/* Start the timer. */
//   	cudaEventCreate(&start); 
//   	cudaEventCreate(&stop); 
//   	cudaEventRecord(start, 0); 
  
//   	/* Execute the kernel. */
//   	dim3 block(_N_, _N_); //threads w x h
//   	dim3 grid(gW, gH); //blocks w x h
//   	queen<<<grid, block>>>(dev_a, sizePerYSeg);

//   	/* Wait for the kernel to complete. Needed for timing. */  
//   	cudaThreadSynchronize();
  	
//   	/* Stop the timer and print the resulting time. */
// 	  cudaEventRecord(stop, 0); 
// 	  cudaEventSynchronize(stop); 
// 	  cudaEventElapsedTime(&elapsedTime, start, stop);
	  
//   	/* Get result from device. */
//   	cudaMemcpy(a, dev_a, sizeof(long) * numberBlocks, cudaMemcpyDeviceToHost); 
  	
//   	//print any cuda error messages
//   	const char* errorString = cudaGetErrorString(cudaGetLastError());
// 	printf("GPU Error: %s\n", errorString);
	
// 	if(sumOnGPU){
// 		printf("Number of Solutions:%d\n", a[0]);
		  
// 		//add cpu time and gpu time and print result
// 		printf( "GPU Time/Total Time: %f secs\n", (elapsedTime / 1000.0));
// 	}
// 	else{
	
// 		/* Start the CPU timer. */
// 		startTime = getTime();
		
// 		int sum = 0;
	
// 		//check if N is even or odd, then calculate sum, which is number of solutions
// 		if(_N_ % 2 == 0){
// 			for(int i = 0; i < numberBlocks; i++){ 
// 				sum+= a[i];
// 			}
// 			sum *= 2;
// 		}
// 		else{
// 			int numBlocksPerSeg = numberBlocks / numBY;
// 			int rowSizeOfGrid = pow(_N_, numBX);
			
// 			for(int j = 0; j < numBY; j++){
// 				int start = j * numBlocksPerSeg;
// 				for(int i = start; i < start + numBlocksPerSeg - rowSizeOfGrid; i++){ 
// 					sum+= a[i];
// 				}
			
// 			}
// 			sum *= 2;
			
// 			//add last block row of sums for each Y block
// 			for(int j = 0; j < numBY; j++){
// 				for(int i = j * numBlocksPerSeg + numBlocksPerSeg - rowSizeOfGrid; i < j * numBlocksPerSeg + numBlocksPerSeg; i++){ 
// 					sum+= a[i];
// 				}
// 			}
			
// 		}
		
// 		/* Stop the CPU timer */
// 		stopTime = getTime();
// 		double totalTime = stopTime - startTime;
		  
// 		printf("Number of Solutions: %d\n", sum);
		  
// 		//add cpu time and gpu time and print result
// 		printf( "GPU Time: %f secs\nCPU Time: %f secs\nTotal Time: %f secs\n", (elapsedTime / 1000.0), totalTime, (elapsedTime / 1000.0) + totalTime );
//   	}
  	
//   	//destroy cuda event
//   	cudaEventDestroy(start); 
//   	cudaEventDestroy(stop);
    	
//   	/* Free the allocated device memory. */
//   	cudaFree(dev_a);
  
//   	//free allocated host memory
// 	free(a);
// }

// __global__
// void queen(long *a, int sizePerYSeg){

// 	__shared__ long solutions[_N_][_N_];
// 	__shared__ char tuple[_N_][_N_][_N_];
	
// 	int totalWrong = 0;
// 	solutions[threadIdx.x][threadIdx.y] = 0;
	
// 	int totNumGen = powf(_N_, numGen);
	
// 	int bYsegment = blockIdx.y / sizePerYSeg;
// 	int workSize = totNumGen / numBY; 
// 	int extra = totNumGen - workSize * numBY;//extra work to be done by last segment
	
// 	//set tuple by block Y value
// 	tuple[threadIdx.x][threadIdx.y][0] = blockIdx.y % sizePerYSeg;
	
// 	//set tuple(s) by block X value
// 	int rem = blockIdx.x;
// 	for(int i = 1; i <= numBX; i++){
// 		tuple[threadIdx.x][threadIdx.y][i] = rem % _N_;
// 		rem = rem / _N_;
// 	}
	
// 	int tupCtr = numBX;
	
// 	//set tuples by thread value
// 	tuple[threadIdx.x][threadIdx.y][++tupCtr] = threadIdx.x;
// 	tuple[threadIdx.x][threadIdx.y][++tupCtr] = threadIdx.y;
	
	
	
// 	//check if thread is valid at this point
// 	for(int i = tupCtr; i > 0; i--){
// 		for(int j = i - 1, ctr = 1; j >= 0; j--, ctr++){
// 			//same row
// 			totalWrong += tuple[threadIdx.x][threadIdx.y][i] == tuple[threadIdx.x][threadIdx.y][j];
			
// 			//diag upleft
// 			totalWrong += (tuple[threadIdx.x][threadIdx.y][i] - ctr) == tuple[threadIdx.x][threadIdx.y][j];
			
// 			//diag downleft
// 			totalWrong += (tuple[threadIdx.x][threadIdx.y][i] + ctr) == tuple[threadIdx.x][threadIdx.y][j]; 
// 		}
// 	}
	
// 	if(totalWrong == 0){
	
// 		//iterate through all numbers to generate possible solutions thread must check
// 		//does not do if thread is already not valid at this point
// 		int start = bYsegment * workSize;
// 		for(int c = start; c < start + workSize + (bYsegment == numBY - 1) * extra; c++){
			
// 			//generate last values in tuple, convert to base N and store to tuple array
// 			int rem = c;
// 			for(int b = 0, k = tupCtr + 1; b < numGen; b++, k++){
// 				tuple[threadIdx.x][threadIdx.y][k] = rem % _N_;
// 				rem = rem / _N_;
// 			}
			
// 			//checks that the numGen tuple values are indeed unique (saves work overall)
// 			for(int x = 0; x < numGen && totalWrong == 0; x++){
// 				for(int y = 0; y < numGen && totalWrong == 0; y++){
// 					totalWrong += tuple[threadIdx.x][threadIdx.y][tupCtr + 1 + x] == tuple[threadIdx.x][threadIdx.y][tupCtr + 1 + y] && x != y;
// 				}
// 			}
			
// 			//check one solution
// 			for(int i = _N_ - 1; i > totalWrong * _N_; i--){
// 				for(int j = i - 1, ctr = 1; j >= 0; j--, ctr++){
// 					//same row
// 					totalWrong += tuple[threadIdx.x][threadIdx.y][i] == tuple[threadIdx.x][threadIdx.y][j];
					
// 					//diag upleft
// 					totalWrong += (tuple[threadIdx.x][threadIdx.y][i] - ctr) == tuple[threadIdx.x][threadIdx.y][j]; 
					
// 					//diag downleft
// 					totalWrong += (tuple[threadIdx.x][threadIdx.y][i] + ctr) == tuple[threadIdx.x][threadIdx.y][j];
// 				}
// 			}
			
// 			//add 1 to solution total if nothing wrong
// 			solutions[threadIdx.x][threadIdx.y] += !(totalWrong);
			
// 			//reset total wrong
// 			totalWrong = 0;
// 		}
	
// 	}
		
// 	//sync the threads so that thread 0 can make the calculations
// 	__syncthreads();
	
// 	//have thread 0 sum for all threads in block to get block total
// 	if(threadIdx.x == 0 && threadIdx.y == 0){
	
// 		//ensure that the block total value is 0 initially
// 		long sum = 0;
		
// 		//iterate through each threads solution and add it to the block total
// 		for(int i =0; i < _N_; i++){
// 			for(int j = 0; j < _N_; j++){
// 				//use local var
// 				sum += solutions[i][j];
// 			}
// 		}
		
// 		//store to global memory
// 		a[gridDim.x * blockIdx.y + blockIdx.x] = sum;
		
// 	}
	
// 	//sync the threads so that calculations can be made
// 	__syncthreads();
	
// 	//have the first thread in the first block sum up the block sums to return to the CPU
// 	if(sumOnGPU == 1 && blockIdx.x == 0 && blockIdx.y == 0 && threadIdx.x == 0 && threadIdx.y == 0){
// 		sumBlocks(a);
// 	}
	
// } 

// __device__
// void sumBlocks(long *a){
// 	long sum = 0;
// 	int numberBlocks = gridDim.x * gridDim.y;
// 	int rowSizeOfGrid = powf(_N_, numBX);

// 	//check if N is even or odd, then calculate sum, which is number of solutions
// 	if(_N_ % 2 == 0){
// 		for(int i = 0; i < numberBlocks; i++){ 
// 			sum+= a[i];
// 		}
// 		sum *= 2;
// 	}
// 	else{
// 		int numBlocksPerSeg = numberBlocks / numBY;
// 		for(int j = 0; j < numBY; j++){
// 			int start = j * numBlocksPerSeg;
// 			for(int i = start; i < start + numBlocksPerSeg - rowSizeOfGrid; i++){ 
// 				sum+= a[i];
// 			}
		
// 		}
// 		sum *= 2;
		
// 		//add last block row of sums for each Y block
// 		for(int j = 0; j < numBY; j++){
// 			for(int i = j * numBlocksPerSeg + numBlocksPerSeg - rowSizeOfGrid; i < j * numBlocksPerSeg + numBlocksPerSeg; i++){ 
// 				sum+= a[i];
// 			}
// 		}
		
// 	}
	
// 	//store sum to first index of a
// 	a[gridDim.x * blockIdx.y + blockIdx.x] = 0;
// 	a[gridDim.x * blockIdx.y + blockIdx.x] = sum;
	
	
// }

// void checkArgs(int argc, char *argv[], int numArgs){
	
// 	//check number of arguments
// 	if(argc  > numArgs){
// 		fprintf(stderr, "\nnqueens: Incorrect number of arguments, %d\nCorrect usage: \"nqueens\"\n", argc - 1);
// 		exit(1);
// 	}
	
	
// 	char* invalChar;
// 	long arg;
	
// 	//check each argument
// 	for(int i = 1; i < numArgs; i++){
// 		//check for overflow of argument
// 		if((arg = strtol(argv[i], &invalChar, 10)) >= INT_MAX){
// 			fprintf(stderr, "\nnqueens: Overflow. Invalid argument %d for nqueens, '%s'.\nThe argument must be a valid, positive, non-zero integer less than %d.\n", i, argv[i], INT_MAX);
// 			exit(1);
// 		}
	
// 		//check that argument is a valid positive integer and check underflow
// 		if(!(arg > 0) || (*invalChar)){
// 			fprintf(stderr, "\nnqueens: Invalid argument %d for nqueens, '%s'.  The argument must be a valid, positive, non-zero integer.\n", i, argv[i]);
// 			exit(1);
// 		}
		
// 	}	
// }

// void checkGPUCapabilities(int gridW, int gridH, int blockW, int blockH, int size){
// 	//check what GPU is being used
// 	int devId;  
// 	cudaGetDevice( &devId );
	
// 	//get device properties for GPU being used
// 	cudaDeviceProp gpuProp;
// 	cudaGetDeviceProperties( &gpuProp, devId );
	
// 	//check if GPU has enough memory 
// 	if(gpuProp.totalGlobalMem < (size * sizeof(long))){
// 		fprintf(stderr, "\nnqueens: Insufficient GPU. GPU does not have enough memory to handle the data size: %ld. It can only handle data sizes up to %ld.\n", (size * sizeof(float)) * 3, gpuProp.totalGlobalMem);
// 		exit(1);
// 	}
	
// 	//check if GPU can handle the number of threads per bloc
// 	if(gpuProp.maxThreadsPerBlock < (blockW * blockH)){
// 		fprintf(stderr, "\nnqueens: Insufficient GPU. GPU can only handle %d threads per block, not %d.\n", gpuProp.maxThreadsPerBlock, (blockW * blockH));
// 		exit(1);
// 	}
	
// 	//check that GPU can handle the number of threads in the block width
// 	if(gpuProp.maxThreadsDim[0] < blockW){
// 		fprintf(stderr, "\nnqueens: Insufficient GPU. GPU can only handle %d threads as the block width of each block, not %d.\n", gpuProp.maxThreadsDim[0], blockW );
// 		exit(1);
// 	}
	
// 	//check that GPU can handle the number of threads in the block height
// 	if(gpuProp.maxThreadsDim[1] < blockH){
// 		fprintf(stderr, "\nnqueens: Insufficient GPU. GPU can only handle %d threads as the block height of each block, not %d.\n", gpuProp.maxThreadsDim[1], blockH );
// 		exit(1);
// 	}
	
// 	//check that GPU can handle the number of blocks in the grid width
// 	if(gpuProp.maxGridSize[0] < gridW){
// 		fprintf(stderr, "\nnqueens: Insufficient GPU. GPU can only handle %d blocks as the grid width of each grid, not %d.\n", gpuProp.maxGridSize[0], gridW );
// 		exit(1);
// 	}
	
// 	//check that GPU can handle the number of blocks in the grid height
// 	if(gpuProp.maxGridSize[1] < gridH){
// 		fprintf(stderr, "\nnqueens: Insufficient GPU. GPU can only handle %d blocks as the grid height of each grid, not %d.\n", gpuProp.maxGridSize[1], gridH );
// 		exit(1);
// 	}
// }

// double getTime(){
//   timeval thetime;
//   gettimeofday(&thetime, 0);
//   return thetime.tv_sec + thetime.tv_usec / 1000000.0;
// }
