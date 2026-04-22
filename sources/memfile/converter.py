input_file = "testImage_1.mem"
output_file = "testImage_1_b.mem"

with open(input_file, "r") as fin, open(output_file, "w") as fout:
    for line in fin:
        content = line.rstrip("\n")
        
        if content == "FF":
            fout.write("01\n")
        else:
            fout.write(line)