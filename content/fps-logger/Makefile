CFLAGS ?= -O2 -Wall
LDFLAGS += -lGL -lX11

fps_logger: fps_logger.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

.PHONY: clean
clean:
	rm -f fps_logger
