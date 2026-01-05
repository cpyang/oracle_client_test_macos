# Makefile for Oracle C++ Test Program

# Compiler
CXX = g++

# Compiler flags
# Ensure ORACLE_HOME is set in your environment.
# For example: export ORACLE_HOME=/path/to/instantclient_19_8
CXXFLAGS = -std=c++11 -I$(ORACLE_HOME)/sdk/include -g -D_GLIBCXX_USE_CXX11_ABI=0

# Linker flags
LDFLAGS = -L$(ORACLE_HOME) -locci -lclntsh -lnnz19 $(ORACLE_HOME)/libclntshcore.so.19.1 -Wl,-rpath,$(ORACLE_HOME)

# Source files
SRCS = src/main.cpp

# Object files
OBJS = $(SRCS:.cpp=.o)

# Executable name
TARGET = build/oracle_test

# Default target
all: $(TARGET)

# Link object files to create the executable
$(TARGET): $(OBJS)
	$(CXX) $(OBJS) -o $(TARGET) $(LDFLAGS)

# Compile source files to object files
%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

# Clean up build artifacts
clean:
	rm -f $(OBJS) $(TARGET)

.PHONY: all clean
