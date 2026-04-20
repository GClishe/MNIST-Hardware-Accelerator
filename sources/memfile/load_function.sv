

string weight_files [0:NUM_PE-1] = '{
	"W_PE1.mem",
	"W_PE2.mem",
	"W_PE3.mem",
	"W_PE4.mem",
	"W_PE5.mem"
};

for (pe = 0; pe < NUM_PE; pe++) begin
	$readmemh(weight_files[pe],RAM[pe]);
end


string bias_files [0:NUM_PE-1] = '{
	"B_PE1.mem",
	"B_PE2.mem",
	"B_PE3.mem",
	"B_PE4.mem",
	"B_PE5.mem"
};

for (pe = 0; pe < NUM_PE; pe++) begin
	$readmemh(bias_files[pe],RAM[pe]);
end