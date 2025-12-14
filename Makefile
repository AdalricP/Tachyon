CC = clang
CFLAGS = -Wall -std=c11 $(shell sdl2-config --cflags) -I/opt/homebrew/include
LIBS = $(shell sdl2-config --libs) -L/opt/homebrew/lib -lmupdf -lmupdf-third -lSDL2_ttf -framework Cocoa

BUILD_DIR = build
TARGET = $(BUILD_DIR)/Tachyon
SRC = src/main.m src/window.m src/file.m src/render.m src/physics.m src/scrollbar.m

all: $(TARGET)

$(TARGET): $(SRC)
	mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC) $(LIBS)

run: $(TARGET)
	./$(TARGET)

clean:
	rm -rf $(BUILD_DIR)

play: clean all run
