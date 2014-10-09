-- resolve and save
for i=0,1000 do if i % 100 == 0 then print("i=",i) end resolve('test'..math.random(1,20000),'32') end for i=0,500 do if i % 100 == 0 then print("i=",i) end save('test'..math.random(1,20000),'status','H','data1','test','data2','test') end

-- resolve and save
for i=0,10000 do if i % 1000 == 0 then print("i=",i) end resolve('test'..i,'32') end
for i=0,10000 do if i % 1000 == 0 then print("i=",i) end save('test'..i,'status','H','data1','test','data2','test') end

-- count
box.space[0]:len()
