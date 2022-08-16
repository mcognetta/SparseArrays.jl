module SparseLinalgTests

using Test
using SparseArrays
using SparseArrays: nonzeroinds, getcolptr
using LinearAlgebra
using Random
include("forbidproperties.jl")

sA = sprandn(3, 7, 0.5)
sC = similar(sA)
dA = Array(sA)

const BASE_TEST_PATH = joinpath(Sys.BINDIR, "..", "share", "julia", "test")
isdefined(Main, :Quaternions) || @eval Main include(joinpath($(BASE_TEST_PATH), "testhelpers", "Quaternions.jl"))
using .Main.Quaternions

@testset "circshift" begin
    m,n = 17,15
    A = sprand(m, n, 0.5)
    for rshift in (-1, 0, 1, 10), cshift in (-1, 0, 1, 10)
        shifts = (rshift, cshift)
        # using dense circshift to compare
        B = circshift(Matrix(A), shifts)
        # sparse circshift
        C = circshift(A, shifts)
        @test C == B
        # sparse circshift should not add structural zeros
        @test nnz(C) == nnz(A)
        # test circshift!
        D = similar(A)
        circshift!(D, A, shifts)
        @test D == B
        @test nnz(D) == nnz(A)
        # test different in/out types
        A2 = floor.(100A)
        E1 = spzeros(Int64, m, n)
        E2 = spzeros(Int64, m, n)
        circshift!(E1, A2, shifts)
        circshift!(E2, Matrix(A2), shifts)
        @test E1 == E2
    end
end

@testset "wrappers of sparse" begin
    m = n = 10
    A = spzeros(ComplexF64, m, n)
    A[:,1] = 1:m
    A[:,2] = [1 3 0 0 0 0 0 0 0 0]'
    A[:,3] = [2 4 0 0 0 0 0 0 0 0]'
    A[:,4] = [0 0 0 0 5 3 0 0 0 0]'
    A[:,5] = [0 0 0 0 6 2 0 0 0 0]'
    A[:,6] = [0 0 0 0 7 4 0 0 0 0]'
    A[:,7:n] = rand(ComplexF64, m, n-6)
    B = Matrix(A)
    dowrap(wr, A) = wr(A)
    dowrap(wr::Tuple, A) = (wr[1])(A, wr[2:end]...)

    @testset "sparse($wr(A))" for wr in (
                        Symmetric, (Symmetric, :L), Hermitian, (Hermitian, :L),
                        Transpose, Adjoint,
                        UpperTriangular, LowerTriangular,
                        UnitUpperTriangular, UnitLowerTriangular,
                        (view, 3:6, 2:5))

        @test SparseMatrixCSC(dowrap(wr, A)) == Matrix(dowrap(wr, B))
    end

    @testset "sparse($at($wr))" for at = (Transpose, Adjoint), wr =
        (UpperTriangular, LowerTriangular,
         UnitUpperTriangular, UnitLowerTriangular)

        @test SparseMatrixCSC(at(wr(A))) == Matrix(at(wr(B)))
    end

    @test sparse([1,2,3,4,5]') == SparseMatrixCSC([1 2 3 4 5])
    @test sparse(UpperTriangular(A')) == UpperTriangular(B')
    @test sparse(Adjoint(UpperTriangular(A'))) == Adjoint(UpperTriangular(B'))
    @test sparse(UnitUpperTriangular(spzeros(5,5))) == I
    deepwrap(A) = (Adjoint(LowerTriangular(view(Symmetric(A), 5:7, 4:6))))
    @test sparse(deepwrap(A)) == Matrix(deepwrap(B))
end

@testset "Sparse promotion in sparse matmul" begin
    A = SparseMatrixCSC{Float32, Int8}(2, 2, Int8[1, 2, 3], Int8[1, 2], Float32[1., 2.])
    B = SparseMatrixCSC{ComplexF32, Int32}(2, 2, Int32[1, 2, 3], Int32[1, 2], ComplexF32[1. + im, 2. - im])
    @test A*transpose(B)                  ≈ Array(A) * transpose(Array(B))
    @test A*adjoint(B)                    ≈ Array(A) * adjoint(Array(B))
    @test transpose(A)*B                  ≈ transpose(Array(A)) * Array(B)
    @test transpose(A)*transpose(B)       ≈ transpose(Array(A)) * transpose(Array(B))
    @test adjoint(B)*A                    ≈ adjoint(Array(B)) * Array(A)
    @test adjoint(B)*adjoint(complex.(A)) ≈ adjoint(Array(B)) * adjoint(Array(complex.(A)))
end

@testset "multiplication of triangular sparse and dense matrices" begin
    n = 7
    B = rand(n, 3)
    _triangular_sparse_matrix(n, ULT, T) = T == Int ? ULT(sparse(rand(0:10, n, n))) : ULT(sprandn(T, n, n, 0.4))
    for T in (Int, Float16, Float32, Float64, ComplexF16, ComplexF32, ComplexF64)
        for AT in (adjoint, transpose)
            for TR in (UpperTriangular, UnitUpperTriangular, LowerTriangular, UnitLowerTriangular)
                TS = AT(_triangular_sparse_matrix(n, TR, T))
                @test isa(TS * B, DenseMatrix)
                @test TS * B ≈ Matrix(TS)*B
            end
        end
    end
end

@testset "sparse transpose adjoint" begin
    A = sprand(10, 10, 0.75)
    @test A' == SparseMatrixCSC(A')
    @test SparseMatrixCSC(A') isa SparseMatrixCSC
    @test transpose(A) == SparseMatrixCSC(transpose(A))
    @test SparseMatrixCSC(transpose(A)) isa SparseMatrixCSC
    @test SparseMatrixCSC{eltype(A)}(transpose(A)) == transpose(A)
    @test SparseMatrixCSC{eltype(A), Int}(transpose(A)) == transpose(A)
    @test SparseMatrixCSC{Float16}(transpose(A)) == transpose(SparseMatrixCSC{Float16}(A))
    @test SparseMatrixCSC{Float16, Int}(transpose(A)) == transpose(SparseMatrixCSC{Float16}(A))
    B = sprand(ComplexF64, 10, 10, 0.75)
    @test SparseMatrixCSC{eltype(B)}(adjoint(B)) == adjoint(B)
    @test SparseMatrixCSC{eltype(B), Int}(adjoint(B)) == adjoint(B)
    @test SparseMatrixCSC{ComplexF16}(adjoint(B)) == adjoint(SparseMatrixCSC{ComplexF16}(B))
    @test SparseMatrixCSC{ComplexF16, Int8}(adjoint(B)) == adjoint(SparseMatrixCSC{ComplexF16, Int8}(B))
end

# PR 28242
@testset "forward and backward solving of transpose/adjoint triangular matrices" begin
    rng = MersenneTwister(20180730)
    n = 10
    A = sprandn(rng, n, n, 0.8); A += Diagonal((1:n) - diag(A))
    B = ones(n, 2)
    for (Ttri, triul ) in ((UpperTriangular, triu), (LowerTriangular, tril))
        for trop in (adjoint, transpose)
            AT = Ttri(A)           # ...Triangular wrapped
            AC = triul(A)          # copied part of A
            ATa = trop(AT)         # wrapped Adjoint
            ACa = sparse(trop(AC)) # copied and adjoint
            @test AT \ B ≈ AC \ B
            @test ATa \ B ≈ ACa \ B
            @test ATa \ sparse(B) == ATa \ B
            @test Matrix(ATa) \ B ≈ ATa \ B
            @test ATa * ( ATa \ B ) ≈ B
        end
    end
end

begin
    rng = Random.MersenneTwister(0)
    n = 1000
    B = ones(n)
    A = sprand(rng, n, n, 0.01)
    MA = Matrix(A)
    lA = sprand(rng, n, n+10, 0.01)
    @testset "triangular multiply with $tr($wr)" for tr in (identity, adjoint, transpose),
    wr in (UpperTriangular, LowerTriangular, UnitUpperTriangular, UnitLowerTriangular)
        AW = tr(wr(A))
        MAW = tr(wr(MA))
        @test AW * B ≈ MAW * B
        # and for SparseMatrixCSCView - a view of all rows and unit range of cols
        vAW = tr(wr(view(A, :, 1:n)))
        vMAW = tr(wr(view(MA, :, 1:n)))
        @test vAW * B ≈ vMAW * B
    end
    A = A - Diagonal(diag(A)) + 2I # avoid rounding errors by division
    MA = Matrix(A)
    @testset "triangular solver for $tr($wr)" for tr in (identity, adjoint, transpose),
    wr in (UpperTriangular, LowerTriangular, UnitUpperTriangular, UnitLowerTriangular)
        AW = tr(wr(A))
        MAW = tr(wr(MA))
        @test AW \ B ≈ MAW \ B
    end
    @testset "triangular singular exceptions" begin
        A = LowerTriangular(sparse([0 2.0;0 1]))
        @test_throws SingularException(1) A \ ones(2)
        A = UpperTriangular(sparse([1.0 0;0 0]))
        @test_throws SingularException(2) A \ ones(2)
    end
end

@testset "Symmetric of sparse matrix mul! dense vector" begin
    rng = Random.MersenneTwister(1)
    n = 1000
    p = 0.02
    q = 1 - sqrt(1-p)
    Areal = sprandn(rng, n, n, p)
    Breal = randn(rng, n)
    Acomplex = sprandn(rng, n, n, q) + sprandn(rng, n, n, q) * im
    Bcomplex = Breal + randn(rng, n) * im
    @testset "symmetric/Hermitian sparse multiply with $S($U)" for S in (Symmetric, Hermitian), U in (:U, :L), (A, B) in ((Areal,Breal), (Acomplex,Bcomplex))
        Asym = S(A, U)
        As = sparse(Asym) # takes most time
        @test which(mul!, (typeof(B), typeof(Asym), typeof(B))).module == SparseArrays
        @test norm(Asym * B - As * B, Inf) <= eps() * n * p * 10
    end
end

@testset "Symmetric of view of sparse matrix mul! dense vector" begin
    rng = Random.MersenneTwister(1)
    n = 1000
    p = 0.02
    q = 1 - sqrt(1-p)
    Areal = view(sprandn(rng, n, n+10, p), :, 6:n+5)
    Breal = randn(rng, n)
    Acomplex = view(sprandn(rng, n, n+10, q) + sprandn(rng, n, n+10, q) * im, :, 6:n+5)
    Bcomplex = Breal + randn(rng, n) * im
    @testset "symmetric/Hermitian sparseview multiply with $S($U)" for S in (Symmetric, Hermitian), U in (:U, :L), (A, B) in ((Areal,Breal), (Acomplex,Bcomplex))
        Asym = S(A, U)
        As = sparse(Asym) # takes most time
        @test which(mul!, (typeof(B), typeof(Asym), typeof(B))).module == SparseArrays
        @test norm(Asym * B - As * B, Inf) <= eps() * n * p * 10
    end
end

@testset "UniformScaling" begin
    local A = sprandn(10, 10, 0.5)
    @test A + I == Array(A) + I
    @test I + A == I + Array(A)
    @test A - I == Array(A) - I
    @test I - A == I - Array(A)
end

@testset "unary minus for SparseMatrixCSC{Bool}" begin
    A = sparse([1,3], [1,3], [true, true])
    B = sparse([1,3], [1,3], [-1, -1])
    @test -A == B
end

@testset "sparse matrix norms" begin
    Ac = sprandn(10,10,.1) + im* sprandn(10,10,.1)
    Ar = sprandn(10,10,.1)
    Ai = ceil.(Int,Ar*100)
    @test opnorm(Ac,1) ≈ opnorm(Array(Ac),1)
    @test opnorm(Ac,Inf) ≈ opnorm(Array(Ac),Inf)
    @test norm(Ac) ≈ norm(Array(Ac))
    @test opnorm(Ar,1) ≈ opnorm(Array(Ar),1)
    @test opnorm(Ar,Inf) ≈ opnorm(Array(Ar),Inf)
    @test norm(Ar) ≈ norm(Array(Ar))
    @test opnorm(Ai,1) ≈ opnorm(Array(Ai),1)
    @test opnorm(Ai,Inf) ≈ opnorm(Array(Ai),Inf)
    @test norm(Ai) ≈ norm(Array(Ai))
    Ai = trunc.(Int, Ar*100)
    @test opnorm(Ai,1) ≈ opnorm(Array(Ai),1)
    @test opnorm(Ai,Inf) ≈ opnorm(Array(Ai),Inf)
    @test norm(Ai) ≈ norm(Array(Ai))
    Ai = round.(Int, Ar*100)
    @test opnorm(Ai,1) ≈ opnorm(Array(Ai),1)
    @test opnorm(Ai,Inf) ≈ opnorm(Array(Ai),Inf)
    @test norm(Ai) ≈ norm(Array(Ai))
    # make certain entries in nzval beyond
    # the range specified in colptr do not
    # impact norm of a sparse matrix
    foo = sparse(1.0I, 4, 4)
    resize!(nonzeros(foo), 5)
    setindex!(nonzeros(foo), NaN, 5)
    @test norm(foo) == 2.0

    # Test (m x 1) sparse matrix
    colM = sprandn(10, 1, 0.6)
    @test opnorm(colM, 1) ≈ opnorm(Array(colM), 1)
    @test opnorm(colM) ≈ opnorm(Array(colM))
    @test opnorm(colM, Inf) ≈ opnorm(Array(colM), Inf)
    @test_throws ArgumentError opnorm(colM, 3)

    # Test (1 x n) sparse matrix
    rowM = sprandn(1, 10, 0.6)
    @test opnorm(rowM, 1) ≈ opnorm(Array(rowM), 1)
    @test opnorm(rowM) ≈ opnorm(Array(rowM))
    @test opnorm(rowM, Inf) ≈ opnorm(Array(rowM), Inf)
    @test_throws ArgumentError opnorm(rowM, 3)
end

@testset "fillstored!" begin
    @test LinearAlgebra.fillstored!(sparse(2.0I, 5, 5), 1) == Matrix(I, 5, 5)
end

@testset "Diagonal linear solve" begin
    n = 12
    for relty in (Float32, Float64), elty in (relty, Complex{relty})
        dd=convert(Vector{elty}, randn(n))
        if elty <: Complex
            dd+=im*convert(Vector{elty}, randn(n))
        end
        D = Diagonal(dd)
        b = rand(elty, n, n)
        b = sparse(b)
        @test ldiv!(D, copy(b)) ≈ Array(D)\Array(b)
        @test_throws SingularException ldiv!(Diagonal(zeros(elty, n)), copy(b))
        b = rand(elty, n+1, n+1)
        b = sparse(b)
        @test_throws DimensionMismatch ldiv!(D, copy(b))
        b = view(rand(elty, n+1), Vector(1:n+1))
        @test_throws DimensionMismatch ldiv!(D, b)
        for b in (sparse(rand(elty,n,n)), sparse(rand(elty,n)))
            @test lmul!(copy(D), copy(b)) ≈ Array(D)*Array(b)
            @test lmul!(transpose(copy(D)), copy(b)) ≈ transpose(Array(D))*Array(b)
            @test lmul!(adjoint(copy(D)), copy(b)) ≈ Array(D)'*Array(b)
        end
    end
end

@testset "triu/tril" begin
    n = 5
    local A = sprand(n, n, 0.2)
    AF = Array(A)
    @test Array(triu(A,1)) == triu(AF,1)
    @test Array(tril(A,1)) == tril(AF,1)
    @test Array(triu!(copy(A), 2)) == triu(AF,2)
    @test Array(tril!(copy(A), 2)) == tril(AF,2)
    @test tril(A, -n - 2) == zero(A)
    @test tril(A, n) == A
    @test triu(A, -n) == A
    @test triu(A, n + 2) == zero(A)

    # fkeep trim option
    @test isequal(length(rowvals(tril!(sparse([1,2,3], [1,2,3], [1,2,3], 3, 4), -1))), 0)
end

@testset "norm" begin
    local A
    A = sparse(Int[],Int[],Float64[],0,0)
    @test norm(A) == zero(eltype(A))
    A = sparse([1.0])
    @test norm(A) == 1.0
    @test_throws ArgumentError opnorm(sprand(5,5,0.2),3)
    @test_throws ArgumentError opnorm(sprand(5,5,0.2),2)
end

@testset "ishermitian/issymmetric" begin
    local A
    # real matrices
    A = sparse(1.0I, 5, 5)
    @test ishermitian(A) == true
    @test issymmetric(A) == true
    A[1,3] = 1.0
    @test ishermitian(A) == false
    @test issymmetric(A) == false
    A[3,1] = 1.0
    @test ishermitian(A) == true
    @test issymmetric(A) == true

    # complex matrices
    A = sparse((1.0 + 1.0im)I, 5, 5)
    @test ishermitian(A) == false
    @test issymmetric(A) == true
    A[1,4] = 1.0 + im
    @test ishermitian(A) == false
    @test issymmetric(A) == false

    A = sparse(ComplexF64(1)I, 5, 5)
    A[3,2] = 1.0 + im
    @test ishermitian(A) == false
    @test issymmetric(A) == false
    A[2,3] = 1.0 - im
    @test ishermitian(A) == true
    @test issymmetric(A) == false

    A = sparse(zeros(5,5))
    @test ishermitian(A) == true
    @test issymmetric(A) == true

    # explicit zeros
    A = sparse(ComplexF64(1)I, 5, 5)
    A[3,1] = 2
    nonzeros(A)[2] = 0.0
    @test ishermitian(A) == true
    @test issymmetric(A) == true

    # 15504
    m = n = 5
    colptr = [1, 5, 9, 13, 13, 17]
    rowval = [1, 2, 3, 5, 1, 2, 3, 5, 1, 2, 3, 5, 1, 2, 3, 5]
    nzval = [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0]
    A = SparseMatrixCSC(m, n, colptr, rowval, nzval)
    @test issymmetric(A) == true
    nonzeros(A)[end - 3]  = 2.0
    @test issymmetric(A) == false

    # 16521
    @test issymmetric(sparse([0 0; 1 0])) == false
    @test issymmetric(sparse([0 1; 0 0])) == false
    @test issymmetric(sparse([0 0; 1 1])) == false
    @test issymmetric(sparse([1 0; 1 0])) == false
    @test issymmetric(sparse([0 1; 1 0])) == true
    @test issymmetric(sparse([1 1; 1 0])) == true
end

@testset "rotations" begin
    a = sparse( [1,1,2,3], [1,3,4,1], [1,2,3,4] )

    @test rot180(a,2) == a
    @test rot180(a,1) == sparse( [3,3,2,1], [4,2,1,4], [1,2,3,4] )
    @test rotr90(a,1) == sparse( [1,3,4,1], [3,3,2,1], [1,2,3,4] )
    @test rotl90(a,1) == sparse( [4,2,1,4], [1,1,2,3], [1,2,3,4] )
    @test rotl90(a,2) == rot180(a)
    @test rotr90(a,2) == rot180(a)
    @test rotl90(a,3) == rotr90(a)
    @test rotr90(a,3) == rotl90(a)

    #ensure we have preserved the correct dimensions!

    a = sparse(1.0I, 3, 5)
    @test size(rot180(a)) == (3,5)
    @test size(rotr90(a)) == (5,3)
    @test size(rotl90(a)) == (5,3)
end

@testset "istriu/istril" begin
    local A = fill(1, 5, 5)
    @test istriu(sparse(triu(A)))
    @test !istriu(sparse(A))
    @test istril(sparse(tril(A)))
    @test !istril(sparse(A))
end

@testset "trace" begin
    @test_throws DimensionMismatch tr(spzeros(5,6))
    @test tr(sparse(1.0I, 5, 5)) == 5
end

@testset "spdiagm" begin
    x = fill(1, 2)
    @test spdiagm(0 => x, -1 => x) == [1 0 0; 1 1 0; 0 1 0]
    @test spdiagm(0 => x,  1 => x) == [1 1 0; 0 1 1; 0 0 0]

    for (x, y) in ((rand(5), rand(4)),(sparse(rand(5)), sparse(rand(4))))
        @test spdiagm(-1 => x)::SparseMatrixCSC         == diagm(-1 => x)
        @test spdiagm( 0 => x)::SparseMatrixCSC         == diagm( 0 => x) == sparse(Diagonal(x))
        @test spdiagm(-1 => x)::SparseMatrixCSC         == diagm(-1 => x)
        @test spdiagm(0 => x, -1 => y)::SparseMatrixCSC == diagm(0 => x, -1 => y)
        @test spdiagm(0 => x,  1 => y)::SparseMatrixCSC == diagm(0 => x,  1 => y)
    end
    # promotion
    @test spdiagm(0 => [1,2], 1 => [3.5], -1 => [4+5im]) == [1 3.5; 4+5im 2]

    # convenience constructor
    @test spdiagm(x)::SparseMatrixCSC == diagm(x)
    @test nnz(spdiagm(x)) == count(!iszero, x)
    @test nnz(spdiagm(sparse([x; 0]))) == 2
    @test spdiagm(3, 4, x)::SparseMatrixCSC == diagm(3, 4, x)
    @test nnz(spdiagm(3, 4, sparse([x; 0]))) == 2

    # non-square:
    for m=1:4, n=2:4
        if m < 2 || n < 3
            @test_throws DimensionMismatch spdiagm(m,n, 0 => x,  1 => x)
        else
            M = zeros(m,n)
            M[1:2,1:3] = [1 1 0; 0 1 1]
            @test spdiagm(m,n, 0 => x,  1 => x) == M
        end
    end

    # sparsity-preservation
    x = sprand(10, 0.2); y = ones(9)
    @test spdiagm(0 => x, 1 => y) == diagm(0 => x, 1 => y)
    @test nnz(spdiagm(0 => x, 1 => y)) == length(y) + nnz(x)
end

@testset "diag" begin
    for T in (Float64, ComplexF64)
        S1 = sprand(T,  5,  5, 0.5)
        S2 = sprand(T, 10,  5, 0.5)
        S3 = sprand(T,  5, 10, 0.5)
        for S in (S1, S2, S3)
            local A = Matrix(S)
            @test diag(S)::SparseVector{T,Int} == diag(A)
            for k in -size(S,1):size(S,2)
                @test diag(S, k)::SparseVector{T,Int} == diag(A, k)
            end
            @test_throws ArgumentError diag(S, -size(S,1)-1)
            @test_throws ArgumentError diag(S,  size(S,2)+1)
        end
    end
    # test that stored zeros are still stored zeros in the diagonal
    S = sparse([1,3],[1,3],[0.0,0.0]); V = diag(S)
    @test nonzeroinds(V) == [1,3]
    @test nonzeros(V) == [0.0,0.0]
end

@testset "scaling with * and mul!, rmul!, and lmul!" begin
    b = randn(7)
    @test dA * Diagonal(b) == sA * Diagonal(b)
    @test dA * Diagonal(b) == mul!(sC, sA, Diagonal(b))
    @test dA * Diagonal(b) == rmul!(copy(sA), Diagonal(b))
    b = randn(3)
    @test Diagonal(b) * dA == Diagonal(b) * sA
    @test Diagonal(b) * dA == mul!(sC, Diagonal(b), sA)
    @test Diagonal(b) * dA == lmul!(Diagonal(b), copy(sA))

    @test dA * 0.5            == sA * 0.5
    @test dA * 0.5            == mul!(sC, sA, 0.5)
    @test dA * 0.5            == rmul!(copy(sA), 0.5)
    @test 0.5 * dA            == 0.5 * sA
    @test 0.5 * dA            == mul!(sC, sA, 0.5)
    @test 0.5 * dA            == lmul!(0.5, copy(sA))
    @test mul!(sC, 0.5, sA)   == mul!(sC, sA, 0.5)

    @testset "inverse scaling with mul!" begin
        bi = inv.(b)
        @test lmul!(Diagonal(bi), copy(dA)) ≈ ldiv!(Diagonal(b), copy(sA))
        @test lmul!(Diagonal(bi), copy(dA)) ≈ ldiv!(transpose(Diagonal(b)), copy(sA))
        @test lmul!(Diagonal(conj(bi)), copy(dA)) ≈ ldiv!(adjoint(Diagonal(b)), copy(sA))
        Aob = Diagonal(b) \ sA
        @test Aob == ldiv!(Diagonal(b), copy(sA))
        @test issparse(Aob)
        @test_throws DimensionMismatch ldiv!(Diagonal(fill(1., length(b)+1)), copy(sA))
        @test_throws LinearAlgebra.SingularException ldiv!(Diagonal(zeros(length(b))), copy(sA))

        dAt = copy(transpose(dA))
        sAt = copy(transpose(sA))
        @test rmul!(copy(dAt), Diagonal(bi)) ≈ rdiv!(copy(sAt), Diagonal(b))
        @test rmul!(copy(dAt), Diagonal(bi)) ≈ rdiv!(copy(sAt), transpose(Diagonal(b)))
        @test rmul!(copy(dAt), Diagonal(conj(bi))) ≈ rdiv!(copy(sAt), adjoint(Diagonal(b)))
        Atob = sAt / Diagonal(b)
        @test Atob == rdiv!(copy(dAt), Diagonal(b))
        @test issparse(Atob)
        @test_throws DimensionMismatch rdiv!(copy(sAt), Diagonal(fill(1., length(b)+1)))
        @test_throws LinearAlgebra.SingularException rdiv!(copy(sAt), Diagonal(zeros(length(b))))
    end

    @testset "non-commutative multiplication" begin
        # non-commutative multiplication
        Avals = Quaternion.(randn(10), randn(10), randn(10), randn(10))
        sA = sparse(rand(1:3, 10), rand(1:7, 10), Avals, 3, 7)
        sC = copy(sA)
        dA = Array(sA)

        b = Quaternion.(randn(7), randn(7), randn(7), randn(7))
        D = Diagonal(b)
        @test Array(sA * D) ≈ dA * D
        @test rmul!(copy(sA), D) ≈ dA * D
        @test mul!(sC, copy(sA), D) ≈ dA * D

        b = Quaternion.(randn(3), randn(3), randn(3), randn(3))
        D = Diagonal(b)
        @test Array(D * sA) ≈ D * dA
        @test lmul!(D, copy(sA)) ≈ D * dA
        @test mul!(sC, D, copy(sA)) ≈ D * dA
    end
end

@testset "conj" begin
    cA = sprandn(5,5,0.2) + im*sprandn(5,5,0.2)
    @test Array(conj.(cA)) == conj(Array(cA))
    @test Array(conj!(copy(cA))) == conj(Array(cA))
end

@testset "SparseMatrixCSC [c]transpose[!] and permute[!]" begin
    smalldim = 5
    largedim = 10
    nzprob = 0.4
    (m, n) = (smalldim, smalldim)
    A = sprand(m, n, nzprob)
    X = similar(A)
    C = copy(transpose(A))
    p = randperm(m)
    q = randperm(n)
    @testset "common error checking of [c]transpose! methods (ftranspose!)" begin
        @test_throws DimensionMismatch transpose!(A[:, 1:(smalldim - 1)], A)
        @test_throws DimensionMismatch transpose!(A[1:(smalldim - 1), 1], A)
    end
    @testset "common error checking of permute[!] methods / source-perm compat" begin
        @test_throws DimensionMismatch permute(A, p[1:(end - 1)], q)
        @test_throws DimensionMismatch permute(A, p, q[1:(end - 1)])
    end
    @testset "common error checking of permute[!] methods / source-dest compat" begin
        @test_throws DimensionMismatch permute!(A[1:(m - 1), :], A, p, q)
        @test_throws DimensionMismatch permute!(A[:, 1:(m - 1)], A, p, q)
        @test_throws ArgumentError permute!((Y = copy(X); resize!(rowvals(Y), nnz(A) - 1); Y), A, p, q)
        @test_throws ArgumentError permute!((Y = copy(X); resize!(nonzeros(Y), nnz(A) - 1); Y), A, p, q)
    end
    @testset "common error checking of permute[!] methods / source-workmat compat" begin
        @test_throws DimensionMismatch permute!(X, A, p, q, C[1:(m - 1), :])
        @test_throws DimensionMismatch permute!(X, A, p, q, C[:, 1:(m - 1)])
        @test_throws ArgumentError permute!(X, A, p, q, (D = copy(C); resize!(rowvals(D), nnz(A) - 1); D))
        @test_throws ArgumentError permute!(X, A, p, q, (D = copy(C); resize!(nonzeros(D), nnz(A) - 1); D))
    end
    @testset "common error checking of permute[!] methods / source-workcolptr compat" begin
        @test_throws DimensionMismatch permute!(A, p, q, C, Vector{eltype(rowvals(A))}(undef, length(getcolptr(A)) - 1))
    end
    @testset "common error checking of permute[!] methods / permutation validity" begin
        @test_throws ArgumentError permute!(A, (r = copy(p); r[2] = r[1]; r), q)
        @test_throws ArgumentError permute!(A, (r = copy(p); r[2] = m + 1; r), q)
        @test_throws ArgumentError permute!(A, p, (r = copy(q); r[2] = r[1]; r))
        @test_throws ArgumentError permute!(A, p, (r = copy(q); r[2] = n + 1; r))
    end
    @testset "overall functionality of [c]transpose[!] and permute[!]" begin
        for (m, n) in ((smalldim, smalldim), (smalldim, largedim), (largedim, smalldim))
            A = sprand(m, n, nzprob)
            At = copy(transpose(A))
            # transpose[!]
            fullAt = Array(transpose(A))
            @test copy(transpose(A)) == fullAt
            @test transpose!(similar(At), A) == fullAt
            # adjoint[!]
            C = A + im*A/2
            fullCh = Array(C')
            @test copy(C') == fullCh
            @test adjoint!(similar(sparse(fullCh)), C) == fullCh
            # permute[!]
            p = randperm(m)
            q = randperm(n)
            fullPAQ = Array(A)[p,q]
            @test permute(A, p, q) == sparse(Array(A[p,q]))
            @test permute!(similar(A), A, p, q) == fullPAQ
            @test permute!(similar(A), A, p, q, similar(At)) == fullPAQ
            @test permute!(copy(A), p, q) == fullPAQ
            @test permute!(copy(A), p, q, similar(At)) == fullPAQ
            @test permute!(copy(A), p, q, similar(At), similar(getcolptr(A))) == fullPAQ
        end
    end
end

@testset "transpose of SubArrays" begin
    A = view(sprandn(10, 10, 0.3), 1:4, 1:4)
    @test copy(transpose(Array(A))) == Array(transpose(A))
    @test copy(adjoint(Array(A))) == Array(adjoint(A))
end

@testset "exp" begin
    A = sprandn(5,5,0.2)
    @test ℯ.^A ≈ ℯ.^Array(A)
end

@testset "matrix-vector multiplication (non-square)" begin
    for i = 1:5
        a = sprand(10, 5, 0.5)
        b = rand(5)
        @test maximum(abs.(a*b - Array(a)*b)) < 100*eps()
    end
end

@testset "sparse matrix * BitArray" begin
    A = sprand(5,5,0.2)
    B = trues(5)
    @test A*B ≈ Array(A)*B
    B = trues(5,5)
    @test A*B ≈ Array(A)*B
    @test B*A ≈ B*Array(A)
end


@testset "matrix multiplication" begin
    for (m, p, n, q, k) in (
                            (10, 0.7, 5, 0.3, 15),
                            (100, 0.01, 100, 0.01, 20),
                            (100, 0.1, 100, 0.2, 100),
                           )
        a = sprand(m, n, p)
        b = sprand(n, k, q)
        as = sparse(a')
        bs = sparse(b')
        ab = a * b
        aab = Array(a) * Array(b)
        @test maximum(abs.(ab - aab)) < 100*eps()
        @test a*bs' == ab
        @test as'*b == ab
        @test as'*bs' == ab
        f = Diagonal(rand(n))
        @test Array(a*f) == Array(a)*f
        @test Array(f*b) == f*Array(b)
        A = rand(2n, 2n)
        sA = view(A, 1:2:2n, 1:2:2n)
        @test Array(sA*b) ≈ Array(sA)*Array(b)
        @test Array(a*sA) ≈ Array(a)*Array(sA)
        c = sprandn(ComplexF32, n, n, q)
        @test Array(sA*c') ≈ Array(sA)*Array(c)'
        @test Array(c'*sA) ≈ Array(c)'*Array(sA)
    end
end

@testset "multiplication of sparse matrix and triangular matrix" begin
    _sparse_test_matrix(n, T) =  T == Int ? sparse(rand(0:4, n, n)) : sprandn(T, n, n, 0.6)
    _triangular_test_matrix(n, TA, T) = T == Int ? TA(rand(0:9, n, n)) : TA(randn(T, n, n))

    n = 5
    for T1 in (Int, Float64, ComplexF32)
        S = _sparse_test_matrix(n, T1)
        MS = Matrix(S)
        for T2 in (Int, Float64, ComplexF32)
            for TM in (LowerTriangular, UnitLowerTriangular, UpperTriangular, UnitLowerTriangular)
                T = _triangular_test_matrix(n, TM, T2)
                MT = Matrix(T)
                @test isa(T * S, DenseMatrix)
                @test isa(S * T, DenseMatrix)
                for transT in (identity, adjoint, transpose), transS in (identity, adjoint, transpose)
                    @test transT(T) * transS(S) ≈ transT(MT) * transS(MS)
                    @test transS(S) * transT(T) ≈ transS(MS) * transT(MT)
                end
            end
        end
    end
end

@testset "Adding sparse-backed SymTridiagonal (#46355)" begin
    a = SymTridiagonal(sparsevec(Int[1]), sparsevec(Int[]))
    @test a + a == Matrix(a) + Matrix(a)

    # symtridiagonal with non-empty off-diagonal
    b = SymTridiagonal(sparsevec(Int[1, 2, 3]), sparsevec(Int[1, 2]))
    @test b + b == Matrix(b) + Matrix(b)

    # a symtridiagonal with an additional off-diagonal element
    c = SymTridiagonal(sparsevec(Int[1, 2, 3]), sparsevec(Int[1, 2, 3]))
    @test c + c == Matrix(c) + Matrix(c)
end

@testset "kronecker product" begin
    for (m,n) in ((5,10), (13,8), (14,10))
        a = sprand(m, 5, 0.4); a_d = Matrix(a)
        b = sprand(n, 6, 0.3); b_d = Matrix(b)
        v = view(a, :, 1); v_d = Vector(v)
        x = sprand(m, 0.4); x_d = Vector(x)
        y = sprand(n, 0.3); y_d = Vector(y)
        c_di = Diagonal(rand(m)); c = sparse(c_di); c_d = Array(c_di)
        d_di = Diagonal(rand(n)); d = sparse(d_di); d_d = Array(d_di)
        # mat ⊗ mat
        for t in (identity, adjoint, transpose)
            @test Array(kron(t(a), b)::SparseMatrixCSC) == kron(t(a_d), b_d)
            @test Array(kron(a, t(b))::SparseMatrixCSC) == kron(a_d, t(b_d))
            @test Array(kron(t(a), t(b))::SparseMatrixCSC) == kron(t(a_d), t(b_d))
            @test Array(kron(a_d, t(b))::SparseMatrixCSC) == kron(a_d, t(b_d))
            @test Array(kron(t(a), b_d)::SparseMatrixCSC) == kron(t(a_d), b_d)
            @test issparse(kron(c, d_di))
            @test Array(kron(c, d_di)) == kron(c_d, d_d)
            @test issparse(kron(c_di, d))
            @test Array(kron(c_di, d)) == kron(c_d, d_d)
            @test issparse(kron(c_di, y))
            @test Array(kron(c_di, y)) == kron(c_di, y_d)
            @test issparse(kron(x, d_di))
            @test Array(kron(x, d_di)) == kron(x_d, d_di)
        end
        # vec ⊗ vec
        @test Vector(kron(x, y)) == kron(x_d, y_d)
        @test Vector(kron(x_d, y)) == kron(x_d, y_d)
        @test Vector(kron(x, y_d)) == kron(x_d, y_d)
        for t in (identity, adjoint, transpose)
            # mat ⊗ vec
            @test Array(kron(t(a), y)::SparseMatrixCSC) == kron(t(a_d), y_d)
            @test Array(kron(t(a_d), y)) == kron(t(a_d), y_d)
            @test Array(kron(t(a), y_d)::SparseMatrixCSC) == kron(t(a_d), y_d)
            # vec ⊗ mat
            @test Array(kron(x, t(b))::SparseMatrixCSC) == kron(x_d, t(b_d))
            @test Array(kron(x_d, t(b))::SparseMatrixCSC) == kron(x_d, t(b_d))
            @test Array(kron(x, t(b_d))) == kron(x_d, t(b_d))
        end
        # vec ⊗ vec'
        @test issparse(kron(v, y'))
        @test issparse(kron(x, y'))
        @test Array(kron(v, y')) == kron(v_d, y_d')
        @test Array(kron(x, y')) == kron(x_d, y_d')
        # test different types
        z = convert(SparseVector{Float16, Int8}, y); z_d = Vector(z)
        @test Vector(kron(x, z)) == kron(x_d, z_d)
        @test Array(kron(a, z)) == kron(a_d, z_d)
        @test Array(kron(z, b)) == kron(z_d, b_d)
    end
end

@testset "sparse Frobenius dot/inner product" begin
    full_view = M -> view(M, :, :)
    for i = 1:5
        A = sprand(ComplexF64,10,15,0.4)
        B = sprand(ComplexF64,10,15,0.5)
        C = rand(10,15) .> 0.3
        @test dot(A,B) ≈ dot(Matrix(A), Matrix(B))
        @test dot(A,B) ≈ dot(A, Matrix(B))
        @test dot(A,B) ≈ dot(Matrix(A), B)
        @test dot(A,C) ≈ dot(Matrix(A), C)
        @test dot(C,A) ≈ dot(C, Matrix(A))
        # square matrices required by most linear algebra wrappers
        SA = A * A'
        SB = B * B'
        SC = C * C'
        for W in (full_view, LowerTriangular, UpperTriangular, UpperHessenberg, Symmetric, Hermitian)
            WA = W(Matrix(SA))
            WB = W(Matrix(SB))
            WC = W(Matrix(SC))
            @test dot(WA,SB) ≈ dot(WA, Matrix(SB))
            @test dot(SA,WB) ≈ dot(Matrix(SA), WB)
            @test dot(SA,WC) ≈ dot(Matrix(SA), WC)
        end
        for W in (transpose, adjoint)
            WA = W(Matrix(A))
            WB = W(Matrix(B))
            WC = W(Matrix(C))
            TA = copy(W(A))
            TB = copy(W(B))
            @test dot(WA,TB) ≈ dot(WA, Matrix(TB))
            @test dot(TA,WB) ≈ dot(Matrix(TA), WB)
            @test dot(TA,WC) ≈ dot(Matrix(TA), WC)
        end
    end
    @test_throws DimensionMismatch dot(sprand(5,5,0.2),sprand(5,6,0.2))
    @test_throws DimensionMismatch dot(rand(5,5),sprand(5,6,0.2))
    @test_throws DimensionMismatch dot(sprand(5,5,0.2),rand(5,6))
end

@testset "generalized dot product" begin
    for i = 1:5
        A = sprand(ComplexF64, 10, 15, 0.4)
        Av = view(A, :, :)
        x = sprand(ComplexF64, 10, 0.5)
        y = sprand(ComplexF64, 15, 0.5)
        @test dot(x, A, y) ≈ dot(Vector(x), A, Vector(y)) ≈ (Vector(x)' * Matrix(A)) * Vector(y)
        @test dot(x, A, y) ≈ dot(x, Av, y)
    end
end

@testset "conversion to special LinearAlgebra types" begin
    # issue 40924
    @test convert(Diagonal, sparse(Diagonal(1:2))) isa Diagonal
    @test convert(Diagonal, sparse(Diagonal(1:2))) == Diagonal(1:2)
    @test convert(Tridiagonal, sparse(Tridiagonal(1:3, 4:7, 8:10))) isa Tridiagonal
    @test convert(Tridiagonal, sparse(Tridiagonal(1:3, 4:7, 8:10))) == Tridiagonal(1:3, 4:7, 8:10)
    @test convert(SymTridiagonal, sparse(SymTridiagonal(1:4, 5:7))) isa SymTridiagonal
    @test convert(SymTridiagonal, sparse(SymTridiagonal(1:4, 5:7))) == SymTridiagonal(1:4, 5:7)

    lt = LowerTriangular([1.0 2.0 3.0; 4.0 5.0 6.0; 7.0 8.0 9.0])
    @test convert(LowerTriangular, sparse(lt)) isa LowerTriangular
    @test convert(LowerTriangular, sparse(lt)) == lt

    ut = UpperTriangular([1.0 2.0 3.0; 4.0 5.0 6.0; 7.0 8.0 9.0])
    @test convert(UpperTriangular, sparse(ut)) isa UpperTriangular
    @test convert(UpperTriangular, sparse(ut)) == ut
end

@testset "SparseMatrixCSC construction from UniformScaling" begin
    @test_throws ArgumentError SparseMatrixCSC(I, -1, 3)
    @test_throws ArgumentError SparseMatrixCSC(I, 3, -1)
    @test SparseMatrixCSC(2I, 3, 3)::SparseMatrixCSC{Int,Int} == Matrix(2I, 3, 3)
    @test SparseMatrixCSC(2I, 3, 4)::SparseMatrixCSC{Int,Int} == Matrix(2I, 3, 4)
    @test SparseMatrixCSC(2I, 4, 3)::SparseMatrixCSC{Int,Int} == Matrix(2I, 4, 3)
    @test SparseMatrixCSC(2.0I, 3, 3)::SparseMatrixCSC{Float64,Int} == Matrix(2I, 3, 3)
    @test SparseMatrixCSC{Real}(2I, 3, 3)::SparseMatrixCSC{Real,Int} == Matrix(2I, 3, 3)
    @test SparseMatrixCSC{Float64}(2I, 3, 3)::SparseMatrixCSC{Float64,Int} == Matrix(2I, 3, 3)
    @test SparseMatrixCSC{Float64,Int32}(2I, 3, 3)::SparseMatrixCSC{Float64,Int32} == Matrix(2I, 3, 3)
    @test SparseMatrixCSC{Float64,Int32}(0I, 3, 3)::SparseMatrixCSC{Float64,Int32} == Matrix(0I, 3, 3)
end
@testset "sparse(S::UniformScaling, shape...) convenience constructors" begin
    # we exercise these methods only lightly as these methods call the SparseMatrixCSC
    # constructor methods well-exercised by the immediately preceding testset
    @test sparse(2I, 3, 4)::SparseMatrixCSC{Int,Int} == Matrix(2I, 3, 4)
    @test sparse(2I, (3, 4))::SparseMatrixCSC{Int,Int} == Matrix(2I, 3, 4)
    @test sparse(3I, 4, 5) == sparse(1:4, 1:4, 3, 4, 5)
    @test sparse(3I, 5, 4) == sparse(1:4, 1:4, 3, 5, 4)
end
end