CC = clang
CFLAGS = -Wall -std=c99 $(shell sdl2-config --cflags)
LIBS = $(shell sdl2-config --libs)

BUILD_DIR = build
TARGET = $(BUILD_DIR)/main
SRC = src/main.c

all: $(TARGET)

$(TARGET): $(SRC)
	mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC) $(LIBS)

run: $(TARGET)
	./$(TARGET)

clean:
	rm -rf $(BUILD_DIR)
