"""
    intersects(μ1, μ2, cov1, cov2, c=2)

Tests whether two hyperellipsoids intersect. The test returns true if 
the hyperellipsoids intersection and false otherwise. 

# Arguments

- `μ1`: centroid of ellipsoid 1 
- `μ2`: centroid of ellipsoid 2
- `cov1`: covariance matrix of ellipsoid 1
- `cov2`: covariance matrix of ellipsoid 2
- `c=2`: ellipse sclar
"""
function intersects(μ1, μ2, cov1, cov2, c=2)
    cov1 .*= c^2
    cov2 .*= c^2
    cho1 = cholesky(cov1)
    inv1 = inv(cho1.U)
     
    _Q2b = inv1' * cov2 * inv1
    Q2b = Symmetric(_Q2b)
    if !issymmetric(_Q2b)
        ϵ = sum(abs.(_Q2b .- _Q2b')) / length(_Q2b)
        if ϵ > 1e-10
            @warn "Q2b is not symmetric: ϵ = $(ϵ).   Q2b = $(Q2b)"
        end
    end
    c2b = inv1' * (μ2 - μ1)
    c2c = (c2b' * inv(cholesky(Q2b).U))'
    v2c = -c2c / sqrt(c2c' * c2c)

    test_point = (v2c' * cholesky(Q2b).U)' .+ c2b
    if test_point' * test_point < 1
        return true 
    elseif all(sign.(test_point) ≠ sign.(c2b))
        return true 
    else
        return false
    end
end

"""
    intersects(chain1, chain2, c=2)

Tests whether two hyperellipsoids intersect. The test returns true if 
the hyperellipsoids intersection and false otherwise. 

# Arguments

- `chain1`: chain object 
- `chain2`: chain object
- `c=2`: ellipse sclar
"""
function intersects(chain1, chain2, c=2)
    mat1 = to_matrix(chain1)
    mat2 = to_matrix(chain2)
    μ1 = mean(mat1, dims=1)[:]
    μ2 = mean(mat2, dims=1)[:]
    cov1 = cov(mat1)
    add_variance!(cov1)
    cov2 = cov(mat2)
    add_variance!(cov2)
    return intersects(μ1, μ2, cov1, cov2)
end

function add_variance!(x)
    if any(x -> isapprox(x, 0), diag(x))
        x[diagind(x)] .== eps()
    end
    return nothing 
end

to_matrix(x) = mapreduce(permutedims, vcat, x.all_parms)

"""
    get_group_indices(chains, chain_indices)

Sorts chains of the same pattern into non-overlapping groups. The vector 
[[1,2],[3,4]] indices chains 1 and 2 are located in region R₁ and chains 
3 and 4 are located in region R₂.

# Arguments

- `chains`: a vector of chains 
- `group`: a vector of indices corresponding to chains with the same pattern
"""
function get_group_indices(chains, chain_indices)
    # group chain indices according to region
    indices = Vector{Vector{Int}}()
    # first index group will have c = 1
    push!(indices, [chain_indices[1]])
    n_groups = length(indices)
    n_chains = length(chain_indices)
    # group index 
    g = 1
    # loop through each chain
    for i ∈ 2:n_chains
        # loop through each index group
        c = chain_indices[i]
        while g ≤ n_groups
            # if chain c matches region index in group g, 
            # push c into index group g
            # (a stand-in for intersection test)
            if intersects(chains[indices[g][1]], chains[c])
                push!(indices[g], c)
                break
            end
            g += 1
        end
        # add new index group
        if g > n_groups
            # add new group
            push!(indices, [c])
            # increment number of groups 
            n_groups += 1
        end
        # reset group counter 
        g = 1
    end
    return indices
end

function remove_redundant_chains!(chains, indices)
    k_indices = Int[]
    for i in indices
        push!(k_indices, i[1])
    end
    r_indices = setdiff(vcat(indices...), k_indices)
    sort!(r_indices)
    deleteat!(chains, r_indices)
    return nothing
end

function group_by_pattern(chains::T) where {T}
    patterns = map(c -> c.pattern, chains)
    u_patterns = unique(patterns)
    n_patterns = length(u_patterns)
    chain_indices = [Vector{Int}() for _ in 1:n_patterns]
    for c in 1:length(chains) 
        g = findfirst(p -> chains[c].pattern == p, u_patterns)
        push!(chain_indices[g], c)
    end
    return chain_indices
end

function make_unique!(chains, options)
    chain_indices = group_by_pattern(chains)
    all_indices = Vector{Vector{Int}}()
    for c in chain_indices
        temp = get_group_indices(chains, c)
        push!(all_indices, temp...)
    end
    merge_chains!(chains, all_indices, options)
    remove_redundant_chains!(chains, all_indices)
    return nothing
end

function merge_chains!(chains, indices, options) 
    return merge_chains!(chains, indices, options.max_merge)
end

function merge_chains!(chains, indices, max_merge::Int)
    max_merge == 0 ? (return nothing) : nothing 
    for idx in indices 
        length(idx) == 1 ? (continue) : nothing
        n = min(length(idx), max_merge + 1)
        for c in 2:n 
            merge_chains!(chains[idx[1]], chains[idx[c]])
        end
    end
    return nothing
end

function merge_chains!(chain1, chain2)
    push!(chain1.all_parms, chain2.all_parms...)
    push!(chain1.acceptance, chain2.acceptance...)
    push!(chain1.radii, chain2.radii...)
    return nothing 
end