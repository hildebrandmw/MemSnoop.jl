#include<iostream>
#include<random>
#include<time.h>
#include<sstream>

// Declare global array size.
const int ARRAY_SIZE = 2000000;

// Basic function to populate a 2D iterator with uniformly distributed real
// numbers between -1.0 and 1.0.
template <class T>
void populate( T& x )
{
    for (auto &i: x) {
        i = i + 1.0;
    }
}

template <class T>
bool timedout( T stoptime ) {
    return clock() > stoptime;
}

template <class T>
void spin( T& array, int spintime ) {
    clock_t stoptime = clock() + spintime * CLOCKS_PER_SEC;
    // Initialiaze
    for (auto &i: array) {
        i = 0.0;
    }
    // Spin
    while ( !timedout(stoptime) ) {
        populate(array);
    } 
}

static double A[ARRAY_SIZE];
static double B[ARRAY_SIZE];

int main(int argc, char *argv[])
{
    // Display addresses of items in memory
    std::cout << &A[0] << "\n";
    std::cout << &B[0] << "\n";

    // Time for population
    int runtime = 4;

    // Spend time doing nothing
    clock_t stoptime = clock() + runtime * CLOCKS_PER_SEC;
    while ( !timedout(stoptime) ) {}

    // Spend time populating "A"
    std::cout << "Populating `A`\n"; 
    spin(A, runtime);
    std::cout << std::accumulate(A, A + ARRAY_SIZE, 0.0) << "\n";

    // Spend time populating "B"
    std::cout << "Populating `B`\n"; 
    spin(B, runtime);
    std::cout << std::accumulate(B, B + ARRAY_SIZE, 0.0) << "\n";

    // Do nothing for a bit longer
    stoptime = clock() + runtime * CLOCKS_PER_SEC;
    while ( !timedout(stoptime) ) {}

    return 0;
}
