
libfast_float: fast_float_strtod.o
	$(AR) -r libfast_float.a fast_float_strtod.o

fast_float_strtod.o: fast_float_strtod.cpp
	$(CXX) -std=c++11 -c fast_float_strtod.cpp

clean:
	rm -f *.o
	rm -f *.a
	rm -f *.h.gch
	rm -rf *.dSYM
