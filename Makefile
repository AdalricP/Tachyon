CC = clang
CFLAGS = -Wall -std=c11 $(shell sdl2-config --cflags) -I/opt/homebrew/include
LIBS = $(shell sdl2-config --libs) -L/opt/homebrew/lib -lmupdf -lmupdf-third -lSDL2_ttf -framework Cocoa

BUILD_DIR = build
TARGET = $(BUILD_DIR)/Tachyon
SRC = src/core/main.m src/ui/window.m src/io/file.m src/render/render.m src/physics/physics.m src/ui/scrollbar.m

all: $(TARGET)

$(TARGET): $(SRC)
	mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC) $(LIBS)

run: $(TARGET)
	./$(TARGET)

clean:
	rm -rf $(BUILD_DIR)

play: clean all run
