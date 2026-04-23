for i in [0,1,2,3,4,5,6,7,8,9]:
    input_file = f"testImage_{i}.mem"
    output_file = f"testImage_{i}_b.mem"

    with open(input_file, "r") as fin, open(output_file, "w") as fout:
        for line in fin:
            content = line.rstrip("\n")
            
            if content == "FF":
                fout.write("100000000\n")
            else:
                fout.write("000000000\n")