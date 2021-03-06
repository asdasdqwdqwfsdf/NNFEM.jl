# tid = parse(Int64, ARGS[1])
force_scale = 6.0 #50
tid = 205
fiber_size = 5
porder = 2
if length(ARGS) == 2
   global force_scale = parse(Float64, ARGS[1])
   global tid = parse(Int64, ARGS[2])
end
printstyled("force_scale=$force_scale, tid=$tid, fiber_size=$fiber_size, porder=$porder\n", color=:green)
include("../CommonFuncs.jl")
np = pyimport("numpy")
"""
Property:
The matrix is made of titanium, which are assumed to be elasto-plastic titanium material,  
time ms
ρ = 4.5 g/cm^3;  E = 100GPa = 	100*10^9 Kg/m/s^2 = 10^6 g/cm/ms^2, K=10e+9Pa =  10^5 g/cm/ms^2
ν =0.2   σY=970 MPa = 9700

Fibers are made of SiC, which are assumed to be isotropic and elastic, with
https://www.azom.com/properties.aspx?ArticleID=42
ρ = 3.2 g/cm^3  E = 400GPa =  4*10^6 g/cm/ms^2  ν = 0.35
length scale cm
"""
prop1 = Dict("name"=> "PlaneStressPlasticity","rho"=> 4.5, "E"=> 1e+6, "nu"=> 0.2,
"sigmaY"=>0.97e+4, "K"=>1e+5)
prop2 = Dict("name"=> "PlaneStress", "rho"=> 3.2, "E"=>4e6, "nu"=>0.35)

# prop1 = prop2
ps1 = PlaneStress(prop1); H1 = ps1.H
ps2 = PlaneStress(prop2); H2 = ps2.H

T = 200.0
NT = 200



nxc, nyc = 80,40
nx, ny =  nxc*fiber_size, nyc*fiber_size
#Type 1=> SiC(fiber), type 0=>Ti(matrix), each fiber has size is k by k
fiber_fraction = 0.25
fiber_distribution = "Uniform"
ele_type = generateEleType(nxc, nyc, fiber_size, fiber_fraction, fiber_distribution)
@show "fiber fraction: ",  sum(ele_type)/(nx*ny)
# matshow(ele_type)
# savefig("test.png")
# error()



nodes, EBC, g, gt, FBC, fext, ft, npoints, node_to_point = BoundaryCondition(tid, nx, ny, porder; force_scale=force_scale)
elements = []
for j = 1:ny
    for i = 1:nx 
        n = (nx*porder+1)*(j-1)*porder + (i-1)porder+1
        #element (i,j)
        if porder == 1
            #   4 ---- 3
            #
            #   1 ---- 2

            elnodes = [n, n + 1, n + 1 + (nx + 1), n + (nx + 1)]
        elseif porder == 2
            #   4 --7-- 3
            #   8   9   6 
            #   1 --5-- 2
            elnodes = [n, n + 2, n + 2 + 2*(2*nx+1),  n + 2*(2*nx+1), n+1, n + 2 + (2*nx+1), n + 1 + 2*(2*nx+1), n + (2*nx+1), n+1+(2*nx+1)]
        else
            error("polynomial order error, porder= ", porder)
        end

        coords = nodes[elnodes,:]
        # 0=> matrix, 1=> fiber
        prop = ele_type[i,j] == 0 ? prop1 : prop2
        push!(elements,SmallStrainContinuum(coords,elnodes, prop, 3))
    end
end


ndofs = 2
domain = Domain(nodes, elements, ndofs, EBC, g, FBC, fext)
setGeometryPoints!(domain, npoints, node_to_point)

state = zeros(domain.neqs)
∂u = zeros(domain.neqs)
globdat = GlobalData(state,zeros(domain.neqs), zeros(domain.neqs),∂u, domain.neqs, gt, ft)

assembleMassMatrix!(globdat, domain)
updateStates!(domain, globdat)


Δt = T/NT



ρ_oo = 0.0
αm = (2*ρ_oo - 1)/(ρ_oo + 1)
αf = ρ_oo/(ρ_oo + 1)

timer = @timed begin
    for i = 1:NT
        @info i, "/" , NT

        solver = NewmarkSolver(Δt, globdat, domain, αm, αf, 1e-4, 1e-6, 10)
        #solver = NewmarkSolver(Δt, globdat, domain, 0.5, 0.5, 1e-4, 1e-6, 10)
        # close("all")
        # visσ(domain)
        # axis("equal")
        # savefig("Debug/$i.png")
        # error()
        # close("all")
        # visσ(domain)
        # # visσ(domain,-1.5e9, 4.5e9)
        # savefig("Debug/terminal$(tid)i=$i.png")
        # if i==75
        #     close("all")
        #     visσ(domain)
        #     # visσ(domain,-1.5e9, 4.5e9)
        #     savefig("Debug/terminal$(tid)i=75.png")
        # end
    end
end

using DelimitedFiles
open("Multiscale$(force_scale)$tid.txt", "a") do io 
    writedlm(io, [force_scale timer[2]])
end
