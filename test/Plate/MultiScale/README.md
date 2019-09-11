Feyel, Frédéric, and Jean-Louis Chaboche. 
"FE2 multiscale approach for modelling the elastoviscoplastic behaviour of long fibre SiC/Ti composite materials." 
Computer methods in applied mechanics and engineering 183.3-4 (2000): 309-330.

Geometry:
The plate size is 30 mm by 5mm 
These fibres are made of SiC with diameter about 0.65mm,
The volume fraction is about 33%. 

Domain: 60k by 10k
fibers: k by k
fiber number 200

Property:
Fibers are made of SiC, which are assumed to be isotropic and elastic, with
https://www.azom.com/properties.aspx?ArticleID=42
ρ = 3200 kg/m^3  E = 400GPa   ν = 0.35
The matrix is made of titanium, which are assumed to be elasto-plastic titanium material,  
ρ = 4500 kg/m^3;  E = 100GPa	 K=10e+9  ν =0.2   σY=970 MPa


```julia
u = [reshape(domain.history["state"][i][(nx+1)*(ny+1)+1:end], ny+1, nx+1)[1,end] for i = 1:length(domain.history["state"])]
```


```julia
u = [reshape(domain.history["state"][i][1:(nx+1)*(ny+1)], ny+1, nx+1)[1,end] for i = 1:length(domain.history["state"])]
```


### Setting Code
tid               description
100               fix bottom, pull from top with F = (0, F1)
101               fix bottom, compress from top with F = (0, -F1)
200               fix left, pull from right with F = (F1, 0)
201               fix left, compress from right with F = (-F1, 0)
202               fix left, bend from right with F = (0, F2)
203               fix left, pull/bend from right with F = (F1/√2, F2/√2)
204         
205
300               fix left, push from bottom with a Gaussian distributed load



screen id                   config
110432.pts-22.icme-share    [50,50,50,50,50,50,50,3]        nn_train

123841.pts-22.icme-share    [50,50,50,50,3]                 nn_train1

125137.pts-22.icme-share    [20,20,20,20,20,20,20,3]        nn_train2