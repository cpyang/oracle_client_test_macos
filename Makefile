# Makefile for Oracle C++ and Objective-C Test Programs

# C++ Compiler
CXX = g++

# C++ Compiler flags
# Ensure ORACLE_HOME is set in your environment.
# For example: export ORACLE_HOME=/path/to/instantclient
CXXFLAGS = -std=c++11 -I$(ORACLE_HOME)/sdk/include -g

# C++ Linker flags for macOS
LDFLAGS = -L$(ORACLE_HOME) -locci -lclntsh -lnnz19 -rpath $(ORACLE_HOME)

# Objective-C Compiler
OCC = clang

# Objective-C Compiler flags
OCFLAGS = -I$(ORACLE_HOME)/sdk/include -g -lobjc

# Objective-C Linker flags for macOS
OBJC_LDFLAGS = -L$(ORACLE_HOME) -lclntsh -lnnz19 -rpath $(ORACLE_HOME)

# C++ Source files
SRCS = src/main.cpp

# C++ Object files
OBJS = build/main_cpp.o

# C++ Executable name
TARGET = build/oracle_test

# Objective-C Source files
OBJC_SRCS = src/main.m

# Objective-C Object files
OBJC_OBJS = build/main_objc.o

# Objective-C Executable name
OBJC_TARGET = build/oracle_test_objc

# Default target
all: $(TARGET) $(OBJC_TARGET)

# Link C++ object files to create the executable
$(TARGET): $(OBJS)
	$(CXX) $^ -o $@ $(LDFLAGS)

# Link Objective-C object files to create the executable
$(OBJC_TARGET): $(OBJC_OBJS)
	$(OCC) $^ -o $@ $(OCFLAGS) $(OBJC_LDFLAGS)

# Compile C++ source files to object files
$(OBJS): $(SRCS)
	$(CXX) $(CXXFLAGS) -c $< -o $@

# Compile Objective-C source files to object files
$(OBJC_OBJS): $(OBJC_SRCS)
	$(OCC) $(OCFLAGS) -c $< -o $@

# Clean up build artifacts
clean:
	rm -f $(OBJS) $(TARGET) $(OBJC_OBJS) $(OBJC_TARGET)

.PHONY: all clean
